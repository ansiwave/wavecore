import puppy

type
  ChannelRef*[T] = ptr Channel[T]
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of SendRequest:
      request: Request
      response: ChannelRef[Result[Response]]
    of QueryUser:
      username: string
      userResponse: ChannelRef[Result[entities.User]]
    of QueryPost:
      postId: int64
      postResponse: ChannelRef[Result[entities.Post]]
    of QueryPostChildren:
      postParentId: int64
      postChildrenResponse: ChannelRef[Result[seq[entities.Post]]]
    dbFilename: string
  Client = ref object
    address*: string
    requestThread: Thread[Client]
    action: ChannelRef[Action]
  ChannelValue*[T] = object
    chan: ChannelRef[Result[T]]
    value*: Result[T]
    ready*: bool

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

proc sendAction*(client: Client, action: Action, cr: ChannelRef) =
  client.action[].send(action)

proc recvAction(client: Client) {.thread.} =
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
  client.requestThread.joinThread()

proc start*(client: var Client) =
  initShared(client)
  initThreads(client)

proc stop*(client: var Client) =
  deinitThreads(client)
  deinitShared(client)

