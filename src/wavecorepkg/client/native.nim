import puppy
from zippy import nil
from urlly import nil
from strutils import nil

from ../db import nil
from ../db/db_sqlite import nil
from ../db/entities import nil

type
  ChannelRef*[T] = ptr Channel[T]
  ResultKind* = enum
    Valid, Error,
  Result*[T] = object
    case kind*: ResultKind
    of Valid:
      valid*: T
    of Error:
      error*: string
  ActionKind* = enum
    Stop, Fetch, QueryUser, QueryPost, QueryPostChildren,
  Action* = object
    case kind*: ActionKind
    of Stop:
      discard
    of Fetch:
      request*: Request
      response*: ChannelRef[Result[Response]]
    of QueryUser:
      publicKey*: string
      userResponse*: ChannelRef[Result[entities.User]]
    of QueryPost:
      postSig*: string
      postResponse*: ChannelRef[Result[entities.Post]]
    of QueryPostChildren:
      postParentSig*: string
      postChildrenResponse*: ChannelRef[Result[seq[entities.Post]]]
    dbFilename*: string
  Client* = ref object
    address*: string
    requestThread*: Thread[Client]
    action*: ChannelRef[Action]
  ChannelValue*[T] = object
    chan*: ChannelRef[Result[T]]
    value*: Result[T]
    ready*: bool

export puppy.fetch, puppy.Request, puppy.Response, puppy.Header

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    chan: cast[ChannelRef[Result[T]]](
      allocShared0(sizeof(Channel[Result[T]]))
    )
  )
  result.chan[].open()

proc get*[T](cv: var ChannelValue[T], blocking: static[bool] = false) =
  if not cv.ready:
    when blocking:
      cv.value = cv.chan[].recv()
      cv.ready = true
      cv.chan[].close()
      deallocShared(cv.chan)
    else:
      let res = cv.chan[].tryRecv()
      if res.dataAvailable:
        cv.value = res.msg
        cv.ready = true
        cv.chan[].close()
        deallocShared(cv.chan)

proc sendAction*(client: Client, action: Action) =
  client.action[].send(action)

proc sendFetch*(client: Client, request: Request, chan: ChannelRef) =
  sendAction(client, Action(kind: Fetch, request: request, response: chan))

proc sendUserQuery*(client: Client, filename: string, publicKey: string, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUser, dbFilename: filename, publicKey: publicKey, userResponse: chan))

proc sendPostQuery*(client: Client, filename: string, sig: string, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPost, dbFilename: filename, postSig: sig, postResponse: chan))

proc sendPostChildrenQuery*(client: Client, filename: string, sig: string, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, postParentSig: sig, postChildrenResponse: chan))

proc recvAction(client: Client) {.thread.} =
  while true:
    let action = client.action[].recv()
    case action.kind:
    of Stop:
      break
    of Fetch:
      try:
        {.cast(gcsafe).}:
          var req = fetch(action.request)
        if req.code == 200:
          if strutils.endsWith(action.request.url.path, ".ansiwavez"):
            req.body = zippy.uncompress(cast[string](req.body), dataFormat = zippy.dfZlib)
          action.response[].send(Result[Response](kind: Valid, valid: req))
        else:
          action.response[].send(Result[Response](kind: Error, error: req.body))
      except Exception as ex:
        action.response[].send(Result[Response](kind: Error, error: ex.msg))
    of QueryUser:
      try:
        let conn = db.open(action.dbFilename, true)
        action.userResponse[].send(Result[entities.User](kind: Valid, valid: entities.selectUser(conn, action.publicKey)))
        db_sqlite.close(conn)
      except Exception as ex:
        action.userResponse[].send(Result[entities.User](kind: Error, error: ex.msg))
    of QueryPost:
      try:
        let conn = db.open(action.dbFilename, true)
        action.postResponse[].send(Result[entities.Post](kind: Valid, valid: entities.selectPost(conn, action.postSig)))
        db_sqlite.close(conn)
      except Exception as ex:
        action.postResponse[].send(Result[entities.Post](kind: Error, error: ex.msg))
    of QueryPostChildren:
      try:
        let conn = db.open(action.dbFilename, true)
        action.postChildrenResponse[].send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectPostChildren(conn, action.postParentSig)))
        db_sqlite.close(conn)
      except Exception as ex:
        action.postChildrenResponse[].send(Result[seq[entities.Post]](kind: Error, error: ex.msg))

proc initShared(client: var Client) =
  client.action = cast[ChannelRef[Action]](
    allocShared0(sizeof(Channel[Action]))
  )
  client.action[].open()

proc deinitShared(client: var Client) =
  client.action[].close()
  deallocShared(client.action)

proc initThreads(client: var Client) =
  createThread(client.requestThread, recvAction, client)

proc deinitThreads(client: var Client) =
  client.action[].send(Action(kind: Stop))
  # FIXME: why can't i do this after updating puppy from 1.0.3 to 1.4.0?
  #client.requestThread.joinThread()

proc start*(client: var Client) =
  initShared(client)
  initThreads(client)

proc stop*(client: var Client) =
  deinitThreads(client)
  deinitShared(client)

