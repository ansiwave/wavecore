from flatty import nil
from flatty/binny import nil
from strutils import nil
import json
import tables
from base64 import nil
from times import nil

from ../db import nil
from ../db/entities import nil
from ../paths import nil

type
  Channel = object
    dataAvailable: bool
    data: string
    url: string
  ChannelPtr* = ptr Channel
  Request* = object
    url*: string
    headers*: seq[Header]
    verb*: string
    body*: string
  Response* = object
    body*: string
    headers*: seq[Header]
    code*: int
  Header* = object
    key*: string
    value*: string
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
    of QueryUser:
      publicKey*: string
    of QueryPost:
      postSig*: string
    of QueryPostChildren:
      postParentSig*: string
      sortBy*: entities.SortBy
    of QueryUserPosts:
      userPostsPublicKey*: string
    of QueryUserReplies:
      userRepliesPublicKey*: string
    of SearchPosts:
      searchKind*: entities.SearchKind
      searchTerm*: string
    dbFilename*: string
    offset: int
  WorkerRequest = object
    action: Action
    channel: int64
  WorkerResponse = object
    data: string
    channel: int64
  ClientKind* = enum
    Online, Offline,
  Client* = ref object
    case kind*: ClientKind
    of Online:
      address*: string
    of Offline:
      discard
    postAddress*: string
    worker: cint
  ChannelValue*[T] = object
    started*: bool
    chan*: ChannelPtr
    value*: Result[T]
    ready*: bool
    readyTime*: float

proc emscripten_create_worker(url: cstring): cint {.importc.}
proc emscripten_destroy_worker(worker: cint) {.importc.}
proc emscripten_call_worker(worker: cint, funcname: cstring, data: cstring, size: cint, callback: proc (data: pointer, size: cint, arg: pointer) {.cdecl.}, arg: pointer) {.importc.}
proc emscripten_worker_respond(data: cstring, size: cint) {.importc.}
proc emscripten_async_wget_data(url: cstring, arg: pointer, onload: pointer, onerror: pointer) {.importc.}
proc wavecore_fetch(url: cstring, verb: cstring, headers: cstring, body: cstring): cstring {.importc.}
proc free(p: pointer) {.importc.}

{.compile: "wavecore_emscripten.c".}

proc fetch*(request: Request): Response =
  let
    url = request.url
    reqHeaders = block:
      var o = json.newJObject()
      for header in request.headers:
        o.fields[header.key] = json.newJString(header.value)
      $o
    res = wavecore_fetch(url.cstring, request.verb, reqHeaders.cstring, request.body)
    json = json.parseJson($res)
    body = base64.decode(json["body"].str)
    code = json["code"].num.int
    resHeaders = block:
      var hs: seq[Header]
      for k, v in json["headers"].fields:
        if v.kind == JString:
          hs.add(Header(key: k, value: v.str))
      hs
  result = Response(body: body, code: code, headers: resHeaders)
  free(res)

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    started: true,
    chan: cast[ChannelPtr](
      allocShared0(sizeof(Channel))
    )
  )

proc get*[T](cv: var ChannelValue[T]) =
  if cv.started and not cv.ready:
    if cv.chan[].dataAvailable:
      cv.value = flatty.fromFlatty(cv.chan[].data, Result[T])
      cv.ready = true
      cv.readyTime = times.epochTime()
      deallocShared(cv.chan)

proc callback(data: pointer, size: cint, arg: pointer) {.cdecl.} =
  var s = newString(size)
  copyMem(s[0].addr, data, size)
  let
    res = flatty.fromFlatty(s, WorkerResponse)
    chan = cast[ptr Channel](res.channel)
  chan[].data = res.data
  chan[].dataAvailable = true

proc sendAction*(client: Client, action: Action, chan: ptr Channel) =
  let data = flatty.toFlatty(WorkerRequest(action: action, channel: cast[int64](chan)))
  emscripten_call_worker(client.worker, "recvAction", data, data.len.cint, callback, nil)

proc sendFetch*(client: Client, request: Request, chan: ChannelPtr) =
  if request.verb != "get" or request.headers.len > 0:
    sendAction(client, Action(kind: Fetch, request: request), chan)
  else:
    chan[].url = request.url

    proc onload(arg: pointer, data: pointer, size: cint) {.cdecl.} =
      var s = newString(size)
      copyMem(s[0].addr, data, size)
      let chan = cast[ptr Channel](arg)
      chan[].data = flatty.toFlatty(Result[Response](kind: Valid, valid: Response(code: 200, body: s)))
      chan[].dataAvailable = true

    proc onerror(arg: pointer) {.cdecl.} =
      let chan = cast[ptr Channel](arg)
      chan[].data = flatty.toFlatty(Result[Response](kind: Error, error: ""))
      chan[].dataAvailable = true

    emscripten_async_wget_data(request.url, chan, onload, onerror)

proc sendUserQuery*(client: Client, filename: string, publicKey: string, chan: ChannelPtr) =
  sendAction(client, Action(kind: QueryUser, dbFilename: filename, publicKey: publicKey), chan)

proc sendPostQuery*(client: Client, filename: string, sig: string, chan: ChannelPtr) =
  sendAction(client, Action(kind: QueryPost, dbFilename: filename, postSig: sig), chan)

proc sendPostChildrenQuery*(client: Client, filename: string, sig: string, sortBy: entities.SortBy, offset: int, chan: ChannelPtr) =
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, sortBy: sortBy, offset: offset, postParentSig: sig), chan)

proc sendUserPostsQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: ChannelPtr) =
  sendAction(client, Action(kind: QueryUserPosts, dbFilename: filename, offset: offset, userPostsPublicKey: publicKey), chan)

proc sendUserRepliesQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: ChannelPtr) =
  sendAction(client, Action(kind: QueryUserReplies, dbFilename: filename, offset: offset, userRepliesPublicKey: publicKey), chan)

proc sendSearchQuery*(client: Client, filename: string, kind: entities.SearchKind, term: string, offset: int, chan: ChannelPtr) =
  sendAction(client, Action(kind: SearchPosts, dbFilename: filename, searchKind: kind, searchTerm: term, offset: offset), chan)

proc recvAction(data: pointer, size: cint) {.exportc.} =
  var input = newString(size)
  copyMem(input[0].addr, data, size)
  let
    workerRequest = flatty.fromFlatty(input, WorkerRequest)
    action = workerRequest.action
  if action.dbFilename != "":
    paths.readUrl = paths.initUrl(paths.address, action.dbFilename)
  let res =
    case action.kind:
    of Stop:
      return
    of Fetch:
      var req = fetch(action.request)
      try:
        if req.code == 200:
          flatty.toFlatty(Result[Response](kind: Valid, valid: req))
        else:
          flatty.toFlatty(Result[Response](kind: Error, error: req.body))
      except Exception as ex:
        flatty.toFlatty(Result[Response](kind: Error, error: ex.msg))
    of QueryUser:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, db.Http):
          let user =
            if entities.existsUser(conn, action.publicKey):
              entities.selectUser(conn, action.publicKey)
            else:
              entities.User()
          s = flatty.toFlatty(Result[entities.User](kind: Valid, valid: user))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryPost:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, db.Http):
          let post = entities.selectPost(conn, action.postSig)
          s = flatty.toFlatty(Result[entities.Post](kind: Valid, valid: post))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryPostChildren:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, db.Http):
          let posts = entities.selectPostChildren(conn, action.postParentSig, action.sortBy, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserPosts:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, db.Http):
          let posts = entities.selectUserPosts(conn, action.userPostsPublicKey, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserReplies:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, db.Http):
          let posts = entities.selectUserReplies(conn, action.userRepliesPublicKey, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of SearchPosts:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, db.Http):
          let posts = entities.search(conn, action.searchKind, action.searchTerm, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
  if res != "":
    let data = flatty.toFlatty(WorkerResponse(data: res, channel: workerRequest.channel))
    emscripten_worker_respond(data, data.len.cint)

proc start*(client: var Client) =
  client.worker = emscripten_create_worker("worker.js")

proc stop*(client: var Client) =
  emscripten_destroy_worker(client.worker)

