import puppy
import json
from strutils import format
from wavecorepkg/db import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/db/db_sqlite import nil

type
  ResultKind* = enum
    Valid, Error,
  Result*[T] = object
    case kind*: ResultKind
    of Valid:
      valid*: T
    of Error:
      error*: ref Exception
  ActionKind = enum
    Stop, SendRequest, QueryUser, QueryPost, QueryPostChildren,
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of SendRequest:
      request: Request
      response: ptr Channel[Result[Response]]
    of QueryUser:
      username: string
      userResponse: ptr Channel[Result[entities.User]]
    of QueryPost:
      postId: int64
      postResponse: ptr Channel[Result[entities.Post]]
    of QueryPostChildren:
      postParentId: int64
      postChildrenResponse: ptr Channel[Result[seq[entities.Post]]]
    dbFilename: string
  Client = ref object
    address*: string
    requestThread: Thread[Client]
    requestReady: ptr Channel[bool]
    action: ptr Channel[Action]
  ClientException* = object of CatchableError

proc initClient*(address: string): Client =
  Client(address: address)

proc sendAction(client: Client, action: Action) =
  client.action[].send(action)

proc initUrl(client: Client; endpoint: string): string =
  "$1/$2".format(client.address, endpoint)

proc request*(client: Client, endpoint: string, data: JsonNode, verb: string): JsonNode =
  let url: string = client.initUrl(endpoint)
  let headers = @[Header(key: "Content-Type", value: "application/json")]
  let response: Response = fetch(Request(url: parseUrl(url), headers: headers, verb: verb, body: if data != nil: $data else: ""))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body.parseJson

proc post*(client: Client, endpoint: string, data: JsonNode): JsonNode =
  request(client, endpoint, data, "post")

proc put*(client: Client, endpoint: string, data: JsonNode): JsonNode =
  request(client, endpoint, data, "put")

proc get*(client: Client, endpoint: string, range: (int, int) = (0, 0)): string =
  let url: string = client.initUrl(endpoint)
  var headers = @[Header(key: "Content-Type", value: "application/json")]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let response: Response = fetch(Request(url: parseUrl(url), headers: headers, verb: "get", body: ""))
  if not response.code in {200, 206}:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc query*(client: Client, endpoint: string, range: (int, int) = (0, 0)): ptr Channel[Result[Response]] =
  let url: string = client.initUrl(endpoint)
  var headers = @[Header(key: "Content-Type", value: "application/json")]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let request = Request(url: parseUrl(url), headers: headers, verb: "get", body: "")
  result = cast[ptr Channel[Result[Response]]](
    allocShared0(sizeof(Channel[Result[Response]]))
  )
  result[].open()
  sendAction(client, Action(kind: SendRequest, request: request, response: result))

proc queryUser*(client: Client, filename: string, username: string): ptr Channel[Result[entities.User]] =
  result = cast[ptr Channel[Result[entities.User]]](
    allocShared0(sizeof(Channel[Result[entities.User]]))
  )
  result[].open()
  sendAction(client, Action(kind: QueryUser, dbFilename: filename, username: username, userResponse: result))

proc queryPost*(client: Client, filename: string, id: int64): ptr Channel[Result[entities.Post]] =
  result = cast[ptr Channel[Result[entities.Post]]](
    allocShared0(sizeof(Channel[Result[entities.Post]]))
  )
  result[].open()
  sendAction(client, Action(kind: QueryPost, dbFilename: filename, postId: id, postResponse: result))

proc queryPostChildren*(client: Client, filename: string, id: int64): ptr Channel[Result[seq[entities.Post]]] =
  result = cast[ptr Channel[Result[seq[entities.Post]]]](
    allocShared0(sizeof(Channel[Result[seq[entities.Post]]]))
  )
  result[].open()
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, postParentId: id, postChildrenResponse: result))

proc recvAction(client: Client) {.thread.} =
  client.requestReady[].send(true)
  while true:
    let action = client.action[].recv()
    case action.kind:
    of Stop:
      break
    of SendRequest:
      try:
        action.response[].send(Result[Response](kind: Valid, valid: fetch(action.request)))
      except Exception as ex:
        action.response[].send(Result[Response](kind: Error, error: ex))
    of QueryUser:
      try:
        let conn = db.open(action.dbFilename, true)
        action.userResponse[].send(Result[entities.User](kind: Valid, valid: entities.selectUser(conn, action.username)))
        db_sqlite.close(conn)
      except Exception as ex:
        action.userResponse[].send(Result[entities.User](kind: Error, error: ex))
    of QueryPost:
      try:
        let conn = db.open(action.dbFilename, true)
        action.postResponse[].send(Result[entities.Post](kind: Valid, valid: entities.selectPost(conn, action.postId)))
        db_sqlite.close(conn)
      except Exception as ex:
        action.postResponse[].send(Result[entities.Post](kind: Error, error: ex))
    of QueryPostChildren:
      try:
        let conn = db.open(action.dbFilename, true)
        action.postChildrenResponse[].send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectPostChildren(conn, action.postParentId)))
        db_sqlite.close(conn)
      except Exception as ex:
        action.postChildrenResponse[].send(Result[seq[entities.Post]](kind: Error, error: ex))

proc initShared(client: var Client) =
  client.requestReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  client.action = cast[ptr Channel[Action]](
    allocShared0(sizeof(Channel[Action]))
  )
  client.requestReady[].open()
  client.action[].open()

proc deinitShared(client: var Client) =
  client.requestReady[].close()
  client.action[].close()
  deallocShared(client.requestReady)
  deallocShared(client.action)

proc initThreads(client: var Client) =
  createThread(client.requestThread, recvAction, client)
  discard client.requestReady[].recv()

proc deinitThreads(client: var Client) =
  client.action[].send(Action(kind: Stop))
  client.requestThread.joinThread()

proc start*(client: var Client) =
  initShared(client)
  initThreads(client)

proc stop*(client: var Client) =
  deinitThreads(client)
  deinitShared(client)

