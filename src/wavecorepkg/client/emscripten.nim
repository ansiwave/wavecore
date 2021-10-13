from urlly import `$`
from flatty import nil
from flatty/binny import nil
from strutils import nil

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

type
  emscripten_fetch_t* {.bycopy.} = object
    id*: cuint                 ##  Unique identifier for this fetch in progress.
    ##  Custom data that can be tagged along the process.
    userData*: pointer         ##  The remote URL that is being downloaded.
    url*: cstring ##  In onsuccess() handler:
                ##    - If the EMSCRIPTEN_FETCH_LOAD_TO_MEMORY attribute was specified for the
                ##      transfer, this points to the body of the downloaded data. Otherwise
                ##      this will be null.
                ##  In onprogress() handler:
                ##    - If the EMSCRIPTEN_FETCH_STREAM_DATA attribute was specified for the
                ##      transfer, this points to a partial chunk of bytes related to the
                ##      transfer. Otherwise this will be null.
                ##  The data buffer provided here has identical lifetime with the
                ##  emscripten_fetch_t object itself, and is freed by calling
                ##  emscripten_fetch_close() on the emscripten_fetch_t pointer.
    data*: cstring ##  Specifies the length of the above data block in bytes. When the download
                 ##  finishes, this field will be valid even if EMSCRIPTEN_FETCH_LOAD_TO_MEMORY
                 ##  was not specified.
    numBytes*: uint64 ##  If EMSCRIPTEN_FETCH_STREAM_DATA is being performed, this indicates the byte
                      ##  offset from the start of the stream that the data block specifies. (for
                      ##  onprogress() streaming XHR transfer, the number of bytes downloaded so far
                      ##  before this chunk)
    dataOffset*: uint64 ##  Specifies the total number of bytes that the response body will be.
                        ##  Note: This field may be zero, if the server does not report the
                        ##  Content-Length field.
    totalBytes*: uint64 ##  Specifies the readyState of the XHR request:
                        ##  0: UNSENT: request not sent yet
                        ##  1: OPENED: emscripten_fetch has been called.
                        ##  2: HEADERS_RECEIVED: emscripten_fetch has been called, and headers and
                        ##     status are available.
                        ##  3: LOADING: download in progress.
                        ##  4: DONE: download finished.
                        ##  See https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest/readyState
    readyState*: cushort       ##  Specifies the status code of the response.
    status*: cushort           ##  Specifies a human-readable form of the status code.
    statusText*: array[64, char]
    proxyState*: uint32    ##  For internal use only.
    #attributes*: emscripten_fetch_attr_t

proc wavecore_fetch(url: cstring): ptr emscripten_fetch_t {.importc.}
proc emscripten_fetch_close(fetch: ptr emscripten_fetch_t): cint {.importc.}

{.compile: "fetch.c".}

proc fetch*(request: Request): Response =
  let
    url = $request.url
    res = wavecore_fetch(url.cstring)
  if res.status == 200:
    var s = newString(res.numBytes)
    copyMem(s[0].addr, res.data, res.numBytes)
    result = Response(body: s, code: 200)
  else:
    result = Response(code: res.status.int)
  echo result
  discard emscripten_fetch_close(res)

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
  case action.kind:
  of Stop:
    return
  of Fetch:
    let
      req = fetch(action.request)
      res =
        if req.code == 200:
          flatty.toFlatty(Result[Response](kind: Valid, valid: req))
        else:
          flatty.toFlatty(Result[Response](kind: Error))
      data = flatty.toFlatty(WorkerResponse(data: res, channel: workerRequest.channel))
    emscripten_worker_respond(data, data.len.cint)
  of QueryPostChildren:
    discard
    #let conn = db.open(action.dbFilename, true)
    #echo entities.selectPostChildren(conn, action.postParentId)
    #db_sqlite.close(conn)
  else:
    return

proc start*(client: var Client) =
  client.worker = emscripten_create_worker("worker.js")

proc stop*(client: var Client) =
  emscripten_destroy_worker(client.worker)

