from urlly import `$`
from flatty import nil
from flatty/binny import nil
from strutils import nil
import json
import tables
from base64 import nil
from zippy import nil
from times import nil

from ../db import nil
from ../db/entities import nil
from ../paths import nil

type
  Channel = object
    dataAvailable: bool
    data: string
    url: string
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
      error*: string
  ActionKind* = enum
    SetReadUrl, Stop, Fetch, QueryUser, QueryPost, QueryPostChildren, QueryUserPosts, QueryUserReplies, SearchPosts,
  Action* = object
    case kind*: ActionKind
    of SetReadUrl:
      readUrl*: string
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
      sortByTs*: bool
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
    chan*: ChannelRef
    value*: Result[T]
    ready*: bool
    readyTime*: float

proc emscripten_create_worker(url: cstring): cint {.importc.}
proc emscripten_destroy_worker(worker: cint) {.importc.}
proc emscripten_call_worker(worker: cint, funcname: cstring, data: cstring, size: cint, callback: proc (data: pointer, size: cint, arg: pointer) {.cdecl.}, arg: pointer) {.importc.}
proc emscripten_worker_respond(data: cstring, size: cint) {.importc.}
proc emscripten_async_wget_data(url: cstring, arg: pointer, onload: pointer, onerror: pointer) {.importc.}
proc wavecore_fetch(url: cstring, verb: cstring, headers: cstring, body: cstring): cstring {.importc.}
proc wavecore_set_innerhtml(selector: cstring, html: cstring) {.importc.}
proc wavecore_set_display(selector: cstring, display: cstring) {.importc.}
proc wavecore_set_size_max(selector: cstring, ratio: cfloat, xadd: cint, yadd: cint) {.importc.}
proc wavecore_browse_file(callback: cstring) {.importc.}
proc wavecore_get_pixel_density(): cfloat {.importc.}
proc wavecore_start_download(data_uri: cstring, filename: cstring) {.importc.}
proc wavecore_localstorage_set(key: cstring, val: cstring): bool {.importc.}
proc wavecore_localstorage_get(key: cstring): cstring {.importc.}
proc wavecore_localstorage_remove(key: cstring) {.importc.}
proc wavecore_localstorage_list(): cstring {.importc.}
proc wavecore_play_audio(src: cstring) {.importc.}
proc wavecore_stop_audio() {.importc.}
proc wavecore_get_hash(): cstring {.importc.}
proc wavecore_set_hash(hash: cstring) {.importc.}
proc wavecore_open_new_tab(url: cstring) {.importc.}
proc wavecore_scroll_up(top: cint) {.importc.}
proc wavecore_scroll_down(bottom: cint) {.importc.}
proc wavecore_copy_text(text: cstring) {.importc.}
proc free(p: pointer) {.importc.}

{.compile: "emscripten.c".}

proc fetch*(request: Request): Response =
  let
    url = $request.url
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

proc setInnerHtml*(selector: string, html: string) =
  wavecore_set_innerhtml(selector, html)

proc setDisplay*(selector: string, display: string) =
  wavecore_set_display(selector, display)

proc setSizeMax*(selector: string, ratio: float32, xadd: int32, yadd: int32) =
  wavecore_set_size_max(selector, ratio, xadd, yadd)

proc browseFile*(callback: string) =
  wavecore_browse_file(callback)

proc getPixelDensity*(): float32 =
  wavecore_get_pixel_density()

proc startDownload*(dataUri: string, filename: string) =
  wavecore_start_download(dataUri, filename)

proc localSet*(key: string, val: string): bool =
  wavecore_localstorage_set(key, val)

proc localGet*(key: string): string =
  let val = wavecore_localstorage_get(key)
  result = $val
  free(val)

proc localRemove*(key: string) =
  wavecore_localstorage_remove(key)

proc localList*(): seq[string] =
  let val = wavecore_localstorage_list()
  for item in parseJson($val):
    result.add(item.str)
  free(val)

proc playAudio*(src: string) =
  wavecore_play_audio(src)

proc stopAudio*() =
  wavecore_stop_audio()

proc copyText*(text: string) =
  wavecore_copy_text(text)

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    started: true,
    chan: cast[ChannelRef](
      allocShared0(sizeof(Channel))
    )
  )

proc getHash*(): string =
  let hash = wavecore_get_hash()
  result = $hash
  free(hash)

proc setHash*(hash: string) =
  wavecore_set_hash(hash)

proc openNewTab*(url: string) =
  wavecore_open_new_tab(url)

proc scrollUp*(top: int32) =
  wavecore_scroll_up(top)

proc scrollDown*(bottom: int32) =
  wavecore_scroll_down(bottom)

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

proc sendSetReadUrl*(client: Client, readUrl: string) =
  let data = flatty.toFlatty(WorkerRequest(action: Action(kind: SetReadUrl, readUrl: readUrl)))
  emscripten_call_worker(client.worker, "recvAction", data, data.len.cint, nil, nil)

proc sendFetch*(client: Client, request: Request, chan: ChannelRef) =
  if request.verb != "get" or request.headers.len > 0:
    sendAction(client, Action(kind: Fetch, request: request), chan)
  else:
    chan[].url = $request.url

    proc onload(arg: pointer, data: pointer, size: cint) {.cdecl.} =
      var s = newString(size)
      copyMem(s[0].addr, data, size)
      let chan = cast[ptr Channel](arg)
      if strutils.endsWith(chan[].url, ".ansiwavez"):
        s = zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib)
      chan[].data = flatty.toFlatty(Result[Response](kind: Valid, valid: Response(code: 200, body: s)))
      chan[].dataAvailable = true

    proc onerror(arg: pointer) {.cdecl.} =
      let chan = cast[ptr Channel](arg)
      chan[].data = flatty.toFlatty(Result[Response](kind: Error, error: ""))
      chan[].dataAvailable = true

    emscripten_async_wget_data($request.url, chan, onload, onerror)

proc sendUserQuery*(client: Client, filename: string, publicKey: string, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUser, dbFilename: filename, publicKey: publicKey), chan)

proc sendPostQuery*(client: Client, filename: string, sig: string, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPost, dbFilename: filename, postSig: sig), chan)

proc sendPostChildrenQuery*(client: Client, filename: string, sig: string, sortByTs: bool, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryPostChildren, dbFilename: filename, sortByTs: sortByTs, offset: offset, postParentSig: sig), chan)

proc sendUserPostsQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUserPosts, dbFilename: filename, offset: offset, userPostsPublicKey: publicKey), chan)

proc sendUserRepliesQuery*(client: Client, filename: string, publicKey: string, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: QueryUserReplies, dbFilename: filename, offset: offset, userRepliesPublicKey: publicKey), chan)

proc sendSearchQuery*(client: Client, filename: string, kind: entities.SearchKind, term: string, offset: int, chan: ChannelRef) =
  sendAction(client, Action(kind: SearchPosts, dbFilename: filename, searchKind: kind, searchTerm: term, offset: offset), chan)

proc recvAction(data: pointer, size: cint) {.exportc.} =
  var input = newString(size)
  copyMem(input[0].addr, data, size)
  let
    workerRequest = flatty.fromFlatty(input, WorkerRequest)
    action = workerRequest.action
  let res =
    case action.kind:
    of SetReadUrl:
      paths.readUrl = action.readUrl
      ""
    of Stop:
      return
    of Fetch:
      var req = fetch(action.request)
      try:
        if req.code == 200:
          if strutils.endsWith(action.request.url.path, ".ansiwavez"):
            req.body = zippy.uncompress(cast[string](req.body), dataFormat = zippy.dfZlib)
          flatty.toFlatty(Result[Response](kind: Valid, valid: req))
        else:
          flatty.toFlatty(Result[Response](kind: Error, error: req.body))
      except Exception as ex:
        flatty.toFlatty(Result[Response](kind: Error, error: ex.msg))
    of QueryUser:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, true):
          let user = entities.selectUser(conn, action.publicKey)
          s = flatty.toFlatty(Result[entities.User](kind: Valid, valid: user))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryPost:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, true):
          let post = entities.selectPost(conn, action.postSig)
          s = flatty.toFlatty(Result[entities.Post](kind: Valid, valid: post))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryPostChildren:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, true):
          let posts = entities.selectPostChildren(conn, action.postParentSig, action.sortByTs, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserPosts:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, true):
          let posts = entities.selectUserPosts(conn, action.userPostsPublicKey, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of QueryUserReplies:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, true):
          let posts = entities.selectUserReplies(conn, action.userRepliesPublicKey, action.offset)
          s = flatty.toFlatty(Result[seq[entities.Post]](kind: Valid, valid: posts))
        s
      except Exception as ex:
        flatty.toFlatty(Result[seq[entities.Post]](kind: Error, error: ex.msg))
    of SearchPosts:
      try:
        var s: string
        db.withOpen(conn, action.dbFilename, true):
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

