import puppy
import json
from uri import nil
from strutils import format

type
  ActionKind = enum
    Stop, SendRequest,
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of SendRequest:
      request: Request
      response: ptr Channel[Response]
  Client = ref object
    address*: string
    requestThread: Thread[Client]
    requestReady: ptr Channel[bool]
    action: ptr Channel[Action]
  ClientException* = object of CatchableError

proc initClient*(address: string): Client =
  Client(address: address)

proc sendRequest(client: Client, request: Request, response: ptr Channel[Response]) =
  var newAction = Action(kind: SendRequest, request: request)
  newAction.response = response
  client.action[].send(newAction)

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

proc get*(client: Client, endpoint: string, response: ptr Channel[Response], range: (int, int) = (0, 0)) =
  let url: string = client.initUrl(endpoint)
  var headers = @[Header(key: "Content-Type", value: "application/json")]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let request = Request(url: parseUrl(url), headers: headers, verb: "get", body: "")
  sendRequest(client, request, response)

proc recvAction(client: Client) {.thread.} =
  client.requestReady[].send(true)
  while true:
    let action = client.action[].recv()
    case action.kind:
    of Stop:
      break
    of SendRequest:
      try:
        action.response[].send(fetch(action.request))
      except Exception as ex:
        discard

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

