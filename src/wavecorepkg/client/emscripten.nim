from urlly import `$`
from flatty import nil
from flatty/binny import nil
from strutils import nil
import json
import tables
from base64 import nil
from zippy import nil

from wavecorepkg/db import nil
from wavecorepkg/db/db_sqlite import nil
from wavecorepkg/db/entities import nil

type
  Channel = object
    dataAvailable: bool
    data: string
  ChannelRef* = ptr Channel
  Request* = object
    url*: urlly.Url
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
      discard
  ActionKind* = enum
    Stop, Fetch, QueryUser, QueryPost, QueryPostChildren,
  Action* = object
    case kind*: ActionKind
    of Stop:
      discard
    of Fetch:
      request*: Request
    of QueryUser:
      username*: string
    of QueryPost:
      postId*: int64
    of QueryPostChildren:
      postParentId*: int64
    dbFilename*: string
  WorkerRequest = object
    action: Action
    channel: int64
  WorkerResponse = object
    data: string
    channel: int64
  Client* = ref object
    address*: string
    worker: cint
  ChannelValue*[T] = object
    chan*: ChannelRef
    value*: Result[T]
    ready*: bool

proc emscripten_create_worker(url: cstring): cint {.importc.}
proc emscripten_destroy_worker(worker: cint) {.importc.}
proc emscripten_call_worker(worker: cint, funcname: cstring, data: cstring, size: cint, callback: proc (data: pointer, size: cint, arg: pointer) {.cdecl.}, arg: pointer) {.importc.}
proc emscripten_worker_respond(data: cstring, size: cint) {.importc.}
proc wavecore_fetch(url: cstring, headers: cstring): cstring {.importc.}
proc free(p: pointer) {.importc.}

{.compile: "fetch.c".}

proc fetch*(request: Request): Response =
  let
    url = $request.url
    reqHeaders = block:
      var o = json.newJObject()
      for header in request.headers:
        o.fields[header.key] = json.newJString(header.value)
      $o
    res = wavecore_fetch(url.cstring, reqHeaders.cstring)
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
    chan: cast[ChannelRef](
      allocShared0(sizeof(Channel))
    )
  )

proc get*[T](cv: var ChannelValue[T]) =
  if not cv.ready:
    if cv.chan[].dataAvailable:
      cv.value = flatty.fromFlatty(cv.chan[].data, Result[T])
      cv.ready = true
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

proc sendFetch*(client: Client, request: Request, chan: ChannelRef) =
  sendAction(client, Action(kind: Fetch, request: request), chan)

proc sendUserQuery*(client: Client, filename: string, username: string, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUser, dbFilename: filename, username: username), chan)

proc sendPostQuery*(client: Client, filename: string, id: int64, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPost, dbFilename: filename, postId: id), chan)

proc sendPostChildrenQuery*(client: Client, filename: string, id: int64, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, postParentId: id), chan)

proc recvAction(data: pointer, size: cint) {.exportc.} =
  var input = newString(size)
  copyMem(input[0].addr, data, size)
  let
    workerRequest = flatty.fromFlatty(input, WorkerRequest)
    action = workerRequest.action
  let res =
    case action.kind:
    of Stop:
      return
    of Fetch:
      var req = fetch(action.request)
      if req.code == 200:
        if strutils.endsWith(action.request.url.path, ".ansiwavez"):
          req.body = zippy.uncompress(cast[string](req.body), dataFormat = zippy.dfZlib)
        flatty.toFlatty(Result[Response](kind: Valid, valid: req))
      else:
        flatty.toFlatty(Result[Response](kind: Error))
    of QueryUser:
      try:
        let conn = db.open(action.dbFilename, true)
        let user = entities.selectUser(conn, action.username)
        db_sqlite.close(conn)
        flatty.toFlatty(Result[entities.User](kind: Valid, valid: user))
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error))
    of QueryPost:
      try:
        let conn = db.open(action.dbFilename, true)
        let post = entities.selectPost(conn, action.postId)
        db_sqlite.close(conn)
        flatty.toFlatty(Result[entities.Post](kind: Valid, valid: post))
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error))
    of QueryPostChildren:
      try:
        let conn = db.open(action.dbFilename, true)
        let posts = entities.selectPostChildren(conn, action.postParentId)
        db_sqlite.close(conn)
        flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error))
  let data = flatty.toFlatty(WorkerResponse(data: res, channel: workerRequest.channel))
  emscripten_worker_respond(data, data.len.cint)

proc start*(client: var Client) =
  client.worker = emscripten_create_worker("worker.js")

proc stop*(client: var Client) =
  emscripten_destroy_worker(client.worker)

