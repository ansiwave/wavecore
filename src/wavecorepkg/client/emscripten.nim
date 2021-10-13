from urlly import nil

type
  ChannelRef*[T] = ref object
    available: bool
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

proc initChannelValue*[T](): ChannelValue[T] =
  result = ChannelValue[T](
    chan: ChannelRef[Result[T]]()
  )

proc get*[T](cv: var ChannelValue[T], blocking: static[bool] = false) =
  if not cv.ready:
    discard

proc sendAction*(client: Client, action: Action, cr: var ChannelRef) =
  proc callback(data: pointer, size: cint, arg: pointer) {.cdecl.} =
    let cr = cast[ptr ChannelRef](arg)[]
    cr.available = true
    if size > 0:
      cr.data = newString(size)
      copyMem(cr.data[0].addr, data, size)
      echo "Output: ", cr.data
  let data = "HI"
  emscripten_call_worker(client.worker, "recvAction", data, data.len.cint, callback, cr.addr)

proc recvAction(data: pointer, size: cint) {.exportc.} =
  var input = newString(size)
  copyMem(input[0].addr, data, size)
  echo "Input: ", input
  let data = "BYE"
  emscripten_worker_respond(data, data.len.cint)

proc start*(client: var Client) =
  client.worker = emscripten_create_worker("worker.js")

proc stop*(client: var Client) =
  emscripten_destroy_worker(client.worker)

