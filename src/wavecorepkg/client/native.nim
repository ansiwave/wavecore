import puppy
from urlly import `$`
from strutils import nil
from times import nil
from os import `/`
import threading/channels

from ../db import nil
from ../db/entities import nil
from ../paths import nil

type
  ResultKind* = enum
    Valid, Error,
  Result*[T] = object
    case kind*: ResultKind
    of Valid:
      valid*: T
    of Error:
      error*: string
  Request* = object
    url*: string
    headers*: seq[Header]
    verb*: string
    body*: string
  Response* = object
    headers*: seq[Header]
    code*: int
    body*: string
  ActionKind* = enum
    Stop, Fetch, QueryUser, QueryPost, QueryPostChildren, QueryUserPosts, QueryUserReplies, SearchPosts,
  Action* = object
    case kind*: ActionKind
    of Stop:
      discard
    of Fetch:
      request*: Request
      response*: Chan[Result[Response]]
    of QueryUser:
      publicKey*: string
      userResponse*: Chan[Result[entities.User]]
    of QueryPost:
      postSig*: string
      postResponse*: Chan[Result[entities.Post]]
    of QueryPostChildren:
      postParentSig*: string
      sortBy*: entities.SortBy
      postChildrenResponse*: Chan[Result[seq[entities.Post]]]
    of QueryUserPosts:
      userPostsPublicKey*: string
      userPostsResponse*: Chan[Result[seq[entities.Post]]]
    of QueryUserReplies:
      userRepliesPublicKey*: string
      userRepliesResponse*: Chan[Result[seq[entities.Post]]]
    of SearchPosts:
      searchKind*: entities.SearchKind
      searchTerm*: string
      searchResponse*: Chan[Result[seq[entities.Post]]]
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
    action*: Chan[Action]
  ChannelValue*[T] = object
    started*: bool
    chan*: Chan[Result[T]]
    value*: Result[T]
    ready*: bool
    readyTime*: float

const channelSize = 100

export puppy.Header

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    started: true,
    chan: newChan[Result[T]](channelSize),
  )

proc get*[T](cv: var ChannelValue[T], blocking: static[bool] = false) =
  if cv.started and not cv.ready:
    when blocking:
      cv.chan.recv(cv.value)
      cv.ready = true
      cv.readyTime = times.epochTime()
    else:
      if cv.chan.tryRecv(cv.value):
        cv.ready = true
        cv.readyTime = times.epochTime()

proc sendAction*(client: Client, action: Action) =
  client.action.send(action)

proc sendFetch*(client: Client, request: Request, chan: Chan) =
  sendAction(client, Action(kind: Fetch, request: request, response: chan))

proc sendUserQuery*(client: Client, filename: string, publicKey: string, chan: Chan) =
  sendAction(client, Action(kind: QueryUser, dbFilename: filename, publicKey: publicKey, userResponse: chan))

proc sendPostQuery*(client: Client, filename: string, sig: string, chan: Chan) =
  sendAction(client, Action(kind: QueryPost, dbFilename: filename, postSig: sig, postResponse: chan))

proc sendPostChildrenQuery*(client: Client, filename: string, sig: string, sortBy: entities.SortBy, offset: int, chan: Chan) =
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, postParentSig: sig, sortBy: sortBy, offset: offset, postChildrenResponse: chan))

proc sendUserPostsQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: Chan) =
  sendAction(client, Action(kind: QueryUserPosts, dbFilename: filename, userPostsPublicKey: publicKey, offset: offset, userPostsResponse: chan))

proc sendUserRepliesQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: Chan) =
  sendAction(client, Action(kind: QueryUserReplies, dbFilename: filename, userRepliesPublicKey: publicKey, offset: offset, userRepliesResponse: chan))

proc sendSearchQuery*(client: Client, filename: string, kind: entities.SearchKind, term: string, offset: int, chan: Chan) =
  sendAction(client, Action(kind: SearchPosts, dbFilename: filename, searchKind: kind, searchTerm: term, offset: offset, searchResponse: chan))

proc trimPath(path: string): string =
  let parts = strutils.split(path, '/')
  if parts.len < 3:
    raise newException(Exception, "Invalid path")
  strutils.join(parts[2 ..< parts.len], "/")

proc toPuppy(request: Request): puppy.Request =
  new result
  result.url = urlly.parseUrl(request.url)
  result.headers = request.headers
  result.verb = request.verb
  result.body = request.body

proc fromPuppy(response: puppy.Response): Response =
  result.headers = response.headers
  result.code = response.code
  result.body = response.body

proc fetch*(request: Request): Response =
  puppy.fetch(request.toPuppy).fromPuppy

proc recvAction(client: Client) {.thread.} =
  while true:
    var action: Action
    client.action.recv(action)
    if client.kind == Online and action.dbFilename != "":
      {.cast(gcsafe).}:
        paths.readUrl = paths.initUrl(paths.address, action.dbFilename)
    case action.kind:
    of Stop:
      break
    of Fetch:
      try:
        let kind =
          # non-get requests always need to be online
          if action.request.verb == "get":
            client.kind
          else:
            Online
        let request = action.request.toPuppy
        case kind:
        of Online:
          {.cast(gcsafe).}:
            var res = fetch(request)
          if res.code == 200:
            action.response.send(Result[Response](kind: Valid, valid: res.fromPuppy))
          else:
            action.response.send(Result[Response](kind: Error, error: res.body))
        of Offline:
          let parts = strutils.split($request.url, '/')
          if parts.len < 3:
            raise newException(Exception, "Invalid path")
          let path = client.path / strutils.join(parts[2 ..< parts.len], "/")
          var res = Response(code: 200, body: readFile(path))
          action.response.send(Result[Response](kind: Valid, valid: res))
      except Exception as ex:
        action.response.send(Result[Response](kind: Error, error: ex.msg))
    of QueryUser:
      try:
        let (path, mode) =
          case client.kind:
          of Online:
            (action.dbFilename, db.Http)
          of Offline:
            (client.path / trimPath(action.dbFilename), db.Read)
        db.withOpen(conn, path, mode):
          if entities.existsUser(conn, action.publicKey):
            action.userResponse.send(Result[entities.User](kind: Valid, valid: entities.selectUser(conn, action.publicKey)))
          else:
            action.userResponse.send(Result[entities.User](kind: Valid, valid: entities.User()))
      except Exception as ex:
        action.userResponse.send(Result[entities.User](kind: Error, error: ex.msg))
    of QueryPost:
      try:
        let (path, mode) =
          case client.kind:
          of Online:
            (action.dbFilename, db.Http)
          of Offline:
            (client.path / trimPath(action.dbFilename), db.Read)
        db.withOpen(conn, path, mode):
          action.postResponse.send(Result[entities.Post](kind: Valid, valid: entities.selectPost(conn, action.postSig)))
      except Exception as ex:
        action.postResponse.send(Result[entities.Post](kind: Error, error: ex.msg))
    of QueryPostChildren:
      try:
        let (path, mode) =
          case client.kind:
          of Online:
            (action.dbFilename, db.Http)
          of Offline:
            (client.path / trimPath(action.dbFilename), db.Read)
        db.withOpen(conn, path, mode):
          action.postChildrenResponse.send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectPostChildren(conn, action.postParentSig, action.sortBy, action.offset)))
      except Exception as ex:
        action.postChildrenResponse.send(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserPosts:
      try:
        let (path, mode) =
          case client.kind:
          of Online:
            (action.dbFilename, db.Http)
          of Offline:
            (client.path / trimPath(action.dbFilename), db.Read)
        db.withOpen(conn, path, mode):
          action.userPostsResponse.send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectUserPosts(conn, action.userPostsPublicKey, action.offset)))
      except Exception as ex:
        action.userPostsResponse.send(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserReplies:
      try:
        let (path, mode) =
          case client.kind:
          of Online:
            (action.dbFilename, db.Http)
          of Offline:
            (client.path / trimPath(action.dbFilename), db.Read)
        db.withOpen(conn, path, mode):
          action.userRepliesResponse.send(Result[seq[entities.Post]](kind: Valid, valid: entities.selectUserReplies(conn, action.userRepliesPublicKey, action.offset)))
      except Exception as ex:
        action.userRepliesResponse.send(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of SearchPosts:
      try:
        let (path, mode) =
          case client.kind:
          of Online:
            (action.dbFilename, db.Http)
          of Offline:
            (client.path / trimPath(action.dbFilename), db.Read)
        db.withOpen(conn, path, mode):
          action.searchResponse.send(Result[seq[entities.Post]](kind: Valid, valid: entities.search(conn, action.searchKind, action.searchTerm, action.offset)))
      except Exception as ex:
        action.searchResponse.send(Result[seq[entities.Post]](kind: Error, error: ex.msg))

proc initChan(client: var Client) =
  client.action = newChan[Action](channelSize)

proc initThreads(client: var Client) =
  createThread(client.requestThread, recvAction, client)

proc deinitThreads(client: var Client) =
  client.action.send(Action(kind: Stop))
  client.requestThread.joinThread()

proc start*(client: var Client) =
  initChan(client)
  initThreads(client)

proc stop*(client: var Client) =
  deinitThreads(client)

