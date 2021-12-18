import puppy
from zippy import nil
from urlly import `$`
from strutils import nil
from times import nil
from os import `/`

from ../db import nil
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
    Stop, Fetch, QueryUser, QueryPost, QueryPostChildren, QueryUserPosts, QueryUserReplies, SearchPosts,
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
      sortByTs*: bool
      postChildrenResponse*: ChannelRef[Result[seq[entities.Post]]]
    of QueryUserPosts:
      userPostsPublicKey*: string
      userPostsResponse*: ChannelRef[Result[seq[entities.Post]]]
    of QueryUserReplies:
      userRepliesPublicKey*: string
      userRepliesResponse*: ChannelRef[Result[seq[entities.Post]]]
    of SearchPosts:
      searchKind*: entities.SearchKind
      searchTerm*: string
      searchResponse*: ChannelRef[Result[seq[entities.Post]]]
    dbFilename*: string
    offset: int
  ClientKind* = enum
    Online, Offline,
  Client* = ref object
    case kind*: ClientKind
    of Online:
      address*: string
    of Offline:
      path*: string
    postAddress*: string
    requestThread*: Thread[Client]
    action*: ChannelRef[Action]
  ChannelValue*[T] = object
    started*: bool
    chan*: ChannelRef[Result[T]]
    value*: Result[T]
    ready*: bool
    readyTime*: float

export puppy.fetch, puppy.Request, puppy.Response, puppy.Header

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    started: true,
    chan: cast[ChannelRef[Result[T]]](
      allocShared0(sizeof(Channel[Result[T]]))
    )
  )
  result.chan[].open()

proc get*[T](cv: var ChannelValue[T], blocking: static[bool] = false) =
  if cv.started and not cv.ready:
    when blocking:
      cv.value = cv.chan[].recv()
      cv.ready = true
      cv.readyTime = times.epochTime()
      cv.chan[].close()
      deallocShared(cv.chan)
    else:
      let res = cv.chan[].tryRecv()
      if res.dataAvailable:
        cv.value = res.msg
        cv.ready = true
        cv.readyTime = times.epochTime()
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

proc sendPostChildrenQuery*(client: Client, filename: string, sig: string, sortByTs: bool, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, postParentSig: sig, sortByTs: sortByTs, offset: offset, postChildrenResponse: chan))

proc sendUserPostsQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUserPosts, dbFilename: filename, userPostsPublicKey: publicKey, offset: offset, userPostsResponse: chan))

proc sendUserRepliesQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUserReplies, dbFilename: filename, userRepliesPublicKey: publicKey, offset: offset, userRepliesResponse: chan))

proc sendSearchQuery*(client: Client, filename: string, kind: entities.SearchKind, term: string, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: SearchPosts, dbFilename: filename, searchKind: kind, searchTerm: term, offset: offset, searchResponse: chan))

proc trimPath(path: string): string =
  let parts = strutils.split(path, '/')
  if parts.len < 3:
    raise newException(Exception, "Invalid path")
  strutils.join(parts[2 ..< parts.len], "/")

proc recvAction(client: Client) {.thread.} =
  while true:
    let action = client.action[].recv()
    case action.kind:
    of Stop:
      break
    of Fetch:
      try:
        case client.kind:
        of Online:
          {.cast(gcsafe).}:
            var res = fetch(action.request)
          if res.code == 200:
            if strutils.endsWith(action.request.url.path, ".ansiwavez"):
              res.body = zippy.uncompress(cast[string](res.body), dataFormat = zippy.dfZlib)
            action.response[].send(Result[Response](kind: Valid, valid: res))
          else:
            action.response[].send(Result[Response](kind: Error, error: res.body))
        of Offline:
          let parts = strutils.split($action.request.url, '/')
          if parts.len < 3:
            raise newException(Exception, "Invalid path")
          let path = client.path / strutils.join(parts[2 ..< parts.len], "/")
          var res = Response(code: 200, body: readFile(path))
          if strutils.endsWith(action.request.url.path, ".ansiwavez"):
            res.body = zippy.uncompress(cast[string](res.body), dataFormat = zippy.dfZlib)
          action.response[].send(Result[Response](kind: Valid, valid: res))
      except Exception as ex:
        action.response[].send(Result[Response](kind: Error, error: ex.msg))
    of QueryUser:
      try:
        let (path, useHttp) =
          case client.kind:
          of Online:
            (action.dbFilename, true)
          of Offline:
            (client.path / trimPath(action.dbFilename), false)
        db.withOpen(conn, path, useHttp):
          action.userResponse[].send(Result[entities.User](kind: Valid, valid: entities.selectUser(conn, action.publicKey)))
      except Exception as ex:
        action.userResponse[].send(Result[entities.User](kind: Error, error: ex.msg))
    of QueryPost:
      try:
        let (path, useHttp) =
          case client.kind:
          of Online:
            (action.dbFilename, true)
          of Offline:
            (client.path / trimPath(action.dbFilename), false)
        db.withOpen(conn, path, useHttp):
          action.postResponse[].send(Result[entities.Post](kind: Valid, valid: entities.selectPost(conn, action.postSig)))
      except Exception as ex:
        action.postResponse[].send(Result[entities.Post](kind: Error, error: ex.msg))
    of QueryPostChildren:
      try:
        let (path, useHttp) =
          case client.kind:
          of Online:
            (action.dbFilename, true)
          of Offline:
            (client.path / trimPath(action.dbFilename), false)
        db.withOpen(conn, path, useHttp):
          action.postChildrenResponse[].send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectPostChildren(conn, action.postParentSig, action.sortByTs, action.offset)))
      except Exception as ex:
        action.postChildrenResponse[].send(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserPosts:
      try:
        let (path, useHttp) =
          case client.kind:
          of Online:
            (action.dbFilename, true)
          of Offline:
            (client.path / trimPath(action.dbFilename), false)
        db.withOpen(conn, path, useHttp):
          action.userPostsResponse[].send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectUserPosts(conn, action.userPostsPublicKey, action.offset)))
      except Exception as ex:
        action.userPostsResponse[].send(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserReplies:
      try:
        let (path, useHttp) =
          case client.kind:
          of Online:
            (action.dbFilename, true)
          of Offline:
            (client.path / trimPath(action.dbFilename), false)
        db.withOpen(conn, path, useHttp):
          action.userRepliesResponse[].send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectUserReplies(conn, action.userRepliesPublicKey, action.offset)))
      except Exception as ex:
        action.userRepliesResponse[].send(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of SearchPosts:
      try:
        let (path, useHttp) =
          case client.kind:
          of Online:
            (action.dbFilename, true)
          of Offline:
            (client.path / trimPath(action.dbFilename), false)
        db.withOpen(conn, path, useHttp):
          action.searchResponse[].send(Result[seq[entities.Post]](kind: Valid, valid: entities.search(conn, action.searchKind, action.searchTerm, action.offset)))
      except Exception as ex:
        action.searchResponse[].send(Result[seq[entities.Post]](kind: Error, error: ex.msg))

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

