import threadpool, net, os, selectors
from uri import `$`
from strutils import nil
from parseutils import nil
from os import joinPath
import httpcore
from ./db import nil
from ./db/entities import nil
from ./db/db_sqlite import nil

type
  State = object
  ActionKind = enum
    Stop, Test,
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of Test:
      success: bool
    done: ptr Channel[bool]
  Server* = ref object
    hostname: string
    port: int
    socket: Socket
    staticFileDir: string
    listenThread, stateThread: Thread[Server]
    listenStopped, listenReady, stateReady: ptr Channel[bool]
    action: ptr Channel[Action]
    state: ptr State
  Request = object
    uri: uri.Uri
    reqMethod: httpcore.HttpMethod
    headers: httpcore.HttpHeaders
    body: string
  BadRequestException = object of CatchableError
  NotFoundException = object of CatchableError
  ForbiddenException = object of CatchableError

const
  selectTimeout =
    when defined(release):
      1000
    # shorter timeout so tests run faster
    else:
      100
  recvTimeout = 2000
  dbFilename* = "board.db"
  ansiwavesDir* = "ansiwaves"

proc initServer*(hostname: string, port: int, staticFileDir: string = ""): Server =
  Server(hostname: hostname, port: port, staticFileDir: staticFileDir)

proc insertUser*(server: Server, entity: entities.User) =
  assert server.staticFileDir != ""
  let conn = db.open(server.staticFileDir.joinPath(dbFilename))
  entities.insertUser(conn, entity,
    proc (x: var entities.User, id: int64) =
      writeFile(server.staticFileDir.joinPath(ansiwavesDir).joinPath($x.public_key & ".ansiwavez"), x.content.value.compressed)
  )
  db_sqlite.close(conn)

proc insertPost*(server: Server, entity: entities.Post) =
  assert server.staticFileDir != ""
  let conn = db.open(server.staticFileDir.joinPath(dbFilename))
  entities.insertPost(conn, entity,
    proc (x: var entities.Post, id: int64) =
      writeFile(server.staticFileDir.joinPath(ansiwavesDir).joinPath($x.content.sig & ".ansiwavez"), x.content.value.compressed)
  )
  db_sqlite.close(conn)

proc sendAction(server: Server, action: Action): bool =
  let done = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  done[].open()
  var newAction = action
  newAction.done = done
  server.action[].send(newAction)
  result = done[].recv()
  done[].close()
  deallocShared(done)

proc test(server: Server, request: Request): string =
  echo request.body
  if true:
    ""
  else:
    raise newException(BadRequestException, "invalid request")

proc handle(server: Server, client: Socket) =
  var headers, body: string
  try:
    var request = Request(headers: httpcore.newHttpHeaders())
    var firstLine = ""
    client.readLine(firstLine, recvTimeout)
    let parts = strutils.split(firstLine, ' ')
    assert parts.len == 3
    # request method
    case parts[0]
    of "GET": request.reqMethod = httpcore.HttpGet
    of "POST": request.reqMethod = httpcore.HttpPost
    of "HEAD": request.reqMethod = httpcore.HttpHead
    of "PUT": request.reqMethod = httpcore.HttpPut
    of "DELETE": request.reqMethod = httpcore.HttpDelete
    of "PATCH": request.reqMethod = httpcore.HttpPatch
    of "OPTIONS": request.reqMethod = httpcore.HttpOptions
    of "CONNECT": request.reqMethod = httpcore.HttpConnect
    of "TRACE": request.reqMethod = httpcore.HttpTrace
    # uri
    request.uri = uri.parseUri(parts[1])
    # headers
    while true:
      # TODO: max number of headers
      var line = ""
      client.readLine(line, recvTimeout)
      if line == "\c\L":
        break
      let (key, value) = httpcore.parseHeader(line)
      request.headers[key] = value
    # body
    if httpcore.hasKey(request.headers, "Content-Length"):
      var contentLength = 0
      if parseutils.parseSaturatedNatural(request.headers["Content-Length"], contentLength) == 0:
        raise newException(BadRequestException, "Bad Request. Invalid Content-Length.")
      else:
        # TODO: max content length
        request.body = client.recv(contentLength)
    # static file requests
    var filePath = ""
    if request.reqMethod == httpcore.HttpGet and server.staticFileDir != "":
      let path = os.joinPath(server.staticFileDir, request.uri.path)
      # TODO: ensure path is inside staticFileDir
      if fileExists(path):
        filePath = path
    if filePath != "":
      let contentType =
        case os.splitFile(filePath).ext:
        of ".html": "text/html"
        of ".js": "text/javascript"
        of ".wasm": "application/wasm"
        else: "text/plain"
      body = readFile(filePath)
      if request.headers.hasKey("Range"):
        let range = strutils.split(strutils.split(request.headers["Range"], '=')[1], '-')
        var first, last: int
        discard parseutils.parseSaturatedNatural(range[0], first)
        discard parseutils.parseSaturatedNatural(range[1], last)
        if first <= last and last < body.len:
          let contentRange = "bytes " & $range[0] & "-" & $range[1] & "/" & $body.len
          body = body[first .. last]
          headers = "HTTP/1.1 206 OK\r\LContent-Length: " & $body.len & "\r\LContent-Range: " & contentRange & "\r\LContent-Type: " & contentType
        else:
          raise newException(BadRequestException, "Bad Request. Invalid Range.")
      else:
        headers = "HTTP/1.1 200 OK\r\LContent-Length: " & $body.len & "\r\LContent-Type: " & contentType
    # json response
    else:
      let dispatch = (reqMethod: request.reqMethod, path: request.uri.path)
      body =
        if dispatch == (httpcore.HttpPost, "/test"):
          test(server, request)
        else:
          raise newException(NotFoundException, "Unhandled request: " & $dispatch)
      headers = "HTTP/1.1 200 OK\r\LContent-Length: " & $body.len
  except BadRequestException as ex:
    headers = "HTTP/1.1 400 Bad Request"
    body = ex.msg
  except ForbiddenException as ex:
    headers = "HTTP/1.1 403 Forbidden"
    body = ex.msg
  except NotFoundException as ex:
    headers = "HTTP/1.1 404 Not Found"
    body = ex.msg
  except Exception as ex:
    headers = "HTTP/1.1 500 Internal Server Error"
    body = ex.msg
  finally:
    try:
      client.send(headers & "\r\L\r\L" & body)
    except Exception as ex:
      discard
    client.close()

proc loop(server: Server) =
  var selector = newSelector[int]()
  selector.registerHandle(server.socket.getFD, {Event.Read}, 0)
  server.listenReady[].send(true)
  while not server.listenStopped[].tryRecv().dataAvailable:
    if selector.select(selectTimeout).len > 0:
      var client: Socket = Socket()
      accept(server.socket, client)
      spawn handle(server, client)

proc listen(server: Server) {.thread.} =
  server.socket = newSocket()
  try:
    server.socket.setSockOpt(OptReuseAddr, true)
    server.socket.bindAddr(port = Port(server.port))
    server.socket.listen()
    echo("Server listening on port " & $server.port)
    server.loop()
  finally:
    echo("Server closing on port " & $server.port)
    server.socket.close()

proc recvAction(server: Server) {.thread.} =
  server.stateReady[].send(true)
  while true:
    let action = server.action[].recv()
    var resp = false
    case action.kind:
    of Stop:
      break
    of Test:
      if action.success:
        resp = true
    action.done[].send(resp)

proc initShared(server: var Server) =
  server.listenStopped = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.listenReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.stateReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.action = cast[ptr Channel[Action]](
    allocShared0(sizeof(Channel[Action]))
  )
  server.listenStopped[].open()
  server.listenReady[].open()
  server.stateReady[].open()
  server.action[].open()
  server.state = cast[ptr State](
    allocShared0(sizeof(State))
  )

proc deinitShared(server: var Server) =
  server.listenStopped[].close()
  server.listenReady[].close()
  server.stateReady[].close()
  server.action[].close()
  deallocShared(server.listenStopped)
  deallocShared(server.listenReady)
  deallocShared(server.stateReady)
  deallocShared(server.action)
  deallocShared(server.state)

proc initThreads(server: var Server) =
  createThread(server.listenThread, listen, server)
  createThread(server.stateThread, recvAction, server)
  discard server.listenReady[].recv()
  discard server.stateReady[].recv()

proc deinitThreads(server: var Server) =
  server.listenStopped[].send(true)
  server.action[].send(Action(kind: Stop))
  server.listenThread.joinThread()
  server.stateThread.joinThread()

proc start*(server: var Server) =
  initShared(server)
  initThreads(server)

proc stop*(server: var Server) =
  deinitThreads(server)
  deinitShared(server)

