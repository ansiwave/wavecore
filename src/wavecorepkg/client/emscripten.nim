from urlly import `$`
from flatty import nil

type
  ChannelRef*[T] = ref object
    dataAvailable: bool
    data: string
  Request* = object
    url*: urlly.Url
    headers*: seq[Header]
    verb*: string
    body*: string
  Response* = object
    body*: string
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
      error*: cint
  ActionKind = enum
    Stop, Fetch, QueryUser, QueryPost, QueryPostChildren,
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of Fetch:
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
    worker: cint
  ChannelValue*[T] = object
    chan: ChannelRef[Result[T]]
    value*: Result[T]
    ready*: bool

proc fetch*(request: Request): Response =
  discard

proc emscripten_create_worker(url: cstring): cint {.importc.}
proc emscripten_destroy_worker(worker: cint) {.importc.}
proc emscripten_call_worker(worker: cint, funcname: cstring, data: cstring, size: cint, callback: proc (data: pointer, size: cint, arg: pointer) {.cdecl.}, arg: pointer) {.importc.}
proc emscripten_worker_respond(data: cstring, size: cint) {.importc.}
proc emscripten_wget_data(url: cstring, pbuffer: pointer, pnum: ptr cint, perror: ptr cint) {.importc.}
proc free(p: pointer) {.importc.}

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    chan: ChannelRef[Result[T]]()
  )

proc get*[T](cv: var ChannelValue[T]) =
  if not cv.ready:
    if cv.chan[].dataAvailable:
      cv.value = flatty.fromFlatty(cv.chan[].data, Result[T])
      cv.ready = true

proc sendAction*(client: Client, action: Action, cr: var ChannelRef) =
  proc callback(data: pointer, size: cint, arg: pointer) {.cdecl.} =
    let cr = cast[ptr ChannelRef](arg)[]
    cr.dataAvailable = true
    if size > 0:
      cr.data = newString(size)
      copyMem(cr.data[0].addr, data, size)
  let data = flatty.toFlatty(action)
  emscripten_call_worker(client.worker, "recvAction", data, data.len.cint, callback, cr.addr)

proc recvAction(data: pointer, size: cint) {.exportc.} =
  var input = newString(size)
  copyMem(input[0].addr, data, size)
  let action = flatty.fromFlatty(input, Action)
  case action.kind:
  of Stop:
    return
  of Fetch:
    var
      buffer: pointer
      size: cint
      error: cint
    emscripten_wget_data($action.request.url, buffer.addr, size.addr, error.addr)
    let data =
      if error == 0:
        var s = newString(size)
        copyMem(s[0].addr, buffer, size)
        free(buffer)
        flatty.toFlatty(Result[Response](kind: Valid, valid: Response(body: s)))
      else:
        flatty.toFlatty(Result[Response](kind: Error, error: error))
    emscripten_worker_respond(data, data.len.cint)
  else:
    return

proc start*(client: var Client) =
  client.worker = emscripten_create_worker("worker.js")

proc stop*(client: var Client) =
  emscripten_destroy_worker(client.worker)

