import threadpool, net, os, selectors
from uri import `$`
from strutils import nil
from parseutils import nil
from os import `/`
import httpcore
from ./db import nil
from ./db/entities import nil
from ./db/db_sqlite import nil
from ./paths import nil
from ./ed25519 import nil
from ./common import nil
import tables

type
  State = object
  ActionKind = enum
    Stop, InsertPost, EditPost,
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of InsertPost:
      post: entities.Post
    of EditPost:
      content: entities.Content
      key: string
    board: string
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

proc initServer*(hostname: string, port: int, staticFileDir: string = ""): Server =
  Server(hostname: hostname, port: port, staticFileDir: staticFileDir)

proc insertPost*(server: Server, board: string, entity: entities.Post) =
  assert server.staticFileDir != ""
  let conn = db.open(server.staticFileDir / paths.db(board))
  db.withTransaction(conn):
    # if user doesn't exist in db, insert it
    try:
      discard entities.selectUser(conn, entity.public_key)
    except Exception as ex:
      entities.insertUser(conn, entities.User(public_key: entity.public_key))
    entities.insertPost(conn, entity,
      proc (x: entities.Post, sig: string) =
        writeFile(server.staticFileDir / paths.ansiwavez(board, sig), x.content.value.compressed)
    )
  db_sqlite.close(conn)

proc editPost*(server: Server, board: string, content: entities.Content, key: string) =
  assert server.staticFileDir != ""
  let conn = db.open(server.staticFileDir / paths.db(board))
  db.withTransaction(conn):
    # if user doesn't exist in db, insert it
    try:
      discard entities.selectUser(conn, key)
    except Exception as ex:
      entities.insertUser(conn, entities.User(public_key: key))
    entities.editPost(conn, content, key,
      proc (x: entities.Post) =
        writeFile(server.staticFileDir / paths.ansiwavez(board, x.content.sig), x.content.value.compressed)
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

proc ansiwavePost(server: Server, request: Request, headers: var string, body: var string) =
  if request.body.len > 0:
    # parse the ansiwave
    let (cmds, headersAndContent, _) =
      try:
        common.parseAnsiwave(request.body)
      except Exception as ex:
        raise newException(BadRequestException, ex.msg)

    # check the board
    let board = cmds["/head.board"]
    if board != paths.encode(paths.decode(board)):
      raise newException(BadRequestException, "Invalid value in /head.board")
    if not os.dirExists(server.staticFileDir / paths.boardsDir / board):
      raise newException(BadRequestException, "Board does not exist")

    # check the sig
    if cmds["/head.algo"] != "ed25519":
      raise newException(BadRequestException, "Invalid value in /head.algo")
    let
      keyBase64 = cmds["/head.key"]
      keyBin = paths.decode(keyBase64)
      sigBase64 = cmds["/head.sig"]
      sigBin = paths.decode(sigBase64)
    var
      pubKey: ed25519.PublicKey
      sig: ed25519.Signature
    if keyBin.len != pubKey.len:
      raise newException(BadRequestException, "Invalid key length for /head.key")
    copyMem(pubKey.addr, keyBin[0].unsafeAddr, keyBin.len)
    if sigBin.len != sig.len:
      raise newException(BadRequestException, "Invalid key length for /head.sig")
    copyMem(sig.addr, sigBin[0].unsafeAddr, sigBin.len)
    if not ed25519.verify(pubKey, sig, headersAndContent):
      raise newException(BadRequestException, "Invalid signature")

    case cmds["/head.type"]:
    of "new":
      let post = entities.Post(
        content: entities.Content(value: entities.initCompressedValue(request.body), sig: sigBase64),
        public_key: keyBase64,
        parent: cmds["/head.target"],
      )
      if not sendAction(server, Action(kind: InsertPost, board: board, post: post)):
        raise newException(Exception, "Failed to insert post")
    of "edit":
      let content = entities.Content(value: entities.initCompressedValue(request.body), sig: sigBase64, sig_last: cmds["/head.target"])
      if not sendAction(server, Action(kind: EditPost, board: board, content: content, key: cmds["/head.key"])):
        raise newException(Exception, "Failed to edit post")
    else:
      raise newException(BadRequestException, "Invalid /head.type")
  else:
    raise newException(BadRequestException, "Invalid request")

  body = ""
  headers = "HTTP/1.1 200 OK\r\LContent-Length: " & $body.len

proc handleStatic(server: Server, request: Request, headers: var string, body: var string): bool =
  var filePath = ""
  if request.reqMethod == httpcore.HttpGet and server.staticFileDir != "":
    let path = server.staticFileDir / request.uri.path
    # TODO: ensure path is inside staticFileDir
    if fileExists(path):
      filePath = path
    else:
      raise newException(NotFoundException, "Not found: " & request.uri.path)
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
    return true
  return false

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
    # handle requests
    let dispatch = (reqMethod: request.reqMethod, path: request.uri.path)
    if dispatch == (httpcore.HttpPost, "/ansiwave"):
      ansiwavePost(server, request, headers, body)
    else:
      when not defined(release):
        if not handleStatic(server, request, headers, body):
          raise newException(NotFoundException, "Unhandled request: " & $dispatch)
      else:
        raise newException(NotFoundException, "Unhandled request: " & $dispatch)
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
  # FIXME: catch exceptions
  while true:
    let action = server.action[].recv()
    var resp = false
    case action.kind:
    of Stop:
      break
    of InsertPost:
      try:
        {.cast(gcsafe).}:
          insertPost(server, action.board, action.post)
        resp = true
      except Exception as ex:
        resp = false
    of EditPost:
      try:
        {.cast(gcsafe).}:
          editPost(server, action.board, action.content, action.key)
        resp = true
      except Exception as ex:
        resp = false
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

