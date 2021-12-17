import threadpool, net, os, selectors
from uri import `$`
from strutils import nil
from parseutils import nil
from os import `/`
from osproc import nil
import httpcore
from ./db import nil
from ./db/entities import nil
from ./paths import nil
from ./ed25519 import nil
from ./common import nil
import tables, sets
from logging import nil

type
  State = object
  ActionKind = enum
    Stop, Log, InsertPost, EditPost, EditTags,
  Action = object
    case kind: ActionKind
    of Stop:
      discard
    of Log:
      message: string
    of InsertPost:
      post: entities.Post
    of EditPost:
      content: entities.Content
    of EditTags:
      tags: entities.Tags
      tagsSigLast: string
    board: string
    key: string
    error: ptr Channel[string]
  Server* = ref object
    hostname: string
    port: int
    socket: Socket
    staticFileDir: string
    outDir: string
    useGit: bool
    listenThread, stateThread: Thread[Server]
    listenStopped, listenReady, stateReady: ptr Channel[bool]
    action: ptr Channel[Action]
    state: ptr State
    initializedBoards: HashSet[string]
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
  maxContentLength = 200000
  maxHeaderCount = 100

proc initServer*(hostname: string, port: int, staticFileDir: string = "", outDir: string = "", useGit: bool = false): Server =
  Server(hostname: hostname, port: port, staticFileDir: staticFileDir, outDir: outDir, useGit: useGit)

proc insertPost*(server: Server, board: string, entity: entities.Post) =
  db.withOpen(conn, server.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      # if user doesn't exist in db, insert it
      try:
        discard entities.selectUser(conn, entity.public_key)
      except Exception as ex:
        entities.insertUser(conn, entities.User(public_key: entity.public_key))
      let sig = entities.insertPost(conn, entity)
      writeFile(server.staticFileDir / paths.ansiwavez(board, sig), entity.content.value.compressed)

proc editPost*(server: Server, board: string, content: entities.Content, key: string) =
  db.withOpen(conn, server.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      # if user doesn't exist in db, insert it
      try:
        discard entities.selectUser(conn, key)
      except Exception as ex:
        entities.insertUser(conn, entities.User(public_key: key))
      let sig = entities.editPost(conn, content, key)
      writeFile(server.staticFileDir / paths.ansiwavez(board, sig), content.value.compressed)

proc editTags*(server: Server, board: string, tags: entities.Tags, tagsSigLast: string, key: string) =
  db.withOpen(conn, server.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      entities.editTags(conn, tags, tagsSigLast, board, key)

proc sendAction(server: Server, action: Action): string =
  let error = cast[ptr Channel[string]](
    allocShared0(sizeof(Channel[string]))
  )
  error[].open()
  var newAction = action
  newAction.error = error
  server.action[].send(newAction)
  result = error[].recv()
  error[].close()
  deallocShared(error)

proc ansiwavePost(server: Server, request: Request, headers: var string, body: var string) =
  if request.body.len == 0:
    raise newException(BadRequestException, "Invalid request")

  # parse the ansiwave
  let (cmds, headersAndContent, contentOnly) =
    try:
      common.parseAnsiwave(request.body)
    except Exception as ex:
      raise newException(BadRequestException, ex.msg)

  # check the board
  let board = cmds["/board"]
  if board != paths.encode(paths.decode(board)):
    raise newException(BadRequestException, "Invalid value in /board")
  if not os.dirExists(server.staticFileDir / paths.boardsDir / board):
    raise newException(BadRequestException, "Board does not exist")

  # check the sig
  if cmds["/algo"] != "ed25519":
    raise newException(BadRequestException, "Invalid value in /algo")
  let
    keyBase64 = cmds["/key"]
    keyBin = paths.decode(keyBase64)
    sigBase64 = cmds["/sig"]
    sigBin = paths.decode(sigBase64)
  var
    pubKey: ed25519.PublicKey
    sig: ed25519.Signature
  if keyBin.len != pubKey.len:
    raise newException(BadRequestException, "Invalid key length for /key")
  copyMem(pubKey.addr, keyBin[0].unsafeAddr, keyBin.len)
  if sigBin.len != sig.len:
    raise newException(BadRequestException, "Invalid key length for /sig")
  copyMem(sig.addr, sigBin[0].unsafeAddr, sigBin.len)
  if not ed25519.verify(pubKey, sig, headersAndContent):
    raise newException(ForbiddenException, "Invalid signature")

  case cmds["/type"]:
  of "new":
    let
      post = entities.Post(
        content: entities.Content(value: entities.initCompressedValue(request.body), sig: sigBase64),
        public_key: keyBase64,
        parent: cmds["/target"],
      )
      error = sendAction(server, Action(kind: InsertPost, board: board, post: post, key: keyBase64))
    if error != "":
      raise newException(Exception, error)
  of "edit":
    let
      content = entities.Content(value: entities.initCompressedValue(request.body), sig: sigBase64, sig_last: cmds["/target"])
      error = sendAction(server, Action(kind: EditPost, board: board, content: content, key: keyBase64))
    if error != "":
      raise newException(Exception, error)
  of "tags":
    let
      tags = entities.Tags(value: request.body, sig: sigBase64)
      error = sendAction(server, Action(kind: EditTags, board: board, tags: tags, tagsSigLast: cmds["/target"], key: keyBase64))
    if error != "":
      raise newException(Exception, error)
  else:
    raise newException(BadRequestException, "Invalid /type")

  body = ""
  headers = "HTTP/1.1 200 OK\r\LContent-Length: " & $body.len

proc handleStatic(server: Server, request: Request, headers: var string, body: var string): bool =
  var filePath = ""
  if request.reqMethod == httpcore.HttpGet and server.staticFileDir != "":
    let path = server.staticFileDir / request.uri.path
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
    if parts.len != 3:
      raise newException(Exception, "Invalid first line: " & firstLine)
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
    var headerCount = 0
    while true:
      if headerCount > maxHeaderCount:
        raise newException(BadRequestException, "Too many headers")
      else:
        headerCount += 1
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
        raise newException(BadRequestException, "Invalid Content-Length")
      elif contentLength > maxContentLength:
        raise newException(BadRequestException, "The Content-Length is too large")
      else:
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
    discard sendAction(server, Action(kind: Log, message: headers & " - " & body))
  except ForbiddenException as ex:
    headers = "HTTP/1.1 403 Forbidden"
    body = ex.msg
    discard sendAction(server, Action(kind: Log, message: headers & " - " & body))
  except NotFoundException as ex:
    headers = "HTTP/1.1 404 Not Found"
    body = ex.msg
    discard sendAction(server, Action(kind: Log, message: headers & " - " & body))
  except Exception as ex:
    headers = "HTTP/1.1 500 Internal Server Error"
    body = ex.msg
    discard sendAction(server, Action(kind: Log, message: headers & " - " & body))
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
  var logger = logging.newConsoleLogger(fmtStr="[$datetime] - $levelname: ")
  server.stateReady[].send(true)
  while true:
    let action = server.action[].recv()
    var resp = ""
    if action.board != "":
      # init board if necessary
      try:
        let bbsGitDir = os.absolutePath(server.staticFileDir / paths.boardsDir / action.board)
        if not os.dirExists(bbsGitDir / paths.ansiwavesDir) or not os.dirExists(bbsGitDir / paths.dbDir):
          os.createDir(bbsGitDir / paths.ansiwavesDir)
          os.createDir(bbsGitDir / paths.dbDir)
          if server.outDir != "":
            let outGitDir = os.absolutePath(server.outDir / paths.boardsDir / action.board)
            if not os.dirExists(bbsGitDir / ".git"):
              discard osproc.execProcess("git", bbsGitDir, args=["init"], options={osproc.poStdErrToStdOut, osproc.poUsePath})
              discard osproc.execProcess("git", bbsGitDir, args=["remote", "add", "out", outGitDir], options={osproc.poStdErrToStdOut, osproc.poUsePath})
              logging.log(logger, logging.lvlInfo, "Created " & bbsGitDir)
            if not os.dirExists(outGitDir):
              os.createDir(os.parentDir(outGitDir))
              discard osproc.execProcess("git", args=["init", "--bare", outGitDir], options={osproc.poStdErrToStdOut, osproc.poUsePath})
              logging.log(logger, logging.lvlInfo, "Created " & outGitDir)
          elif server.useGit:
            if not os.dirExists(bbsGitDir / ".git"):
              discard osproc.execProcess("git", bbsGitDir, args=["init"], options={osproc.poStdErrToStdOut, osproc.poUsePath})
              logging.log(logger, logging.lvlInfo, "Created " & bbsGitDir)
        if action.board notin server.initializedBoards:
          db.withOpen(conn, server.staticFileDir / paths.db(action.board), false):
            db.init(conn)
          server.initializedBoards.incl(action.board)
      except Exception as ex:
        resp = "Error initializing board"
        logging.log(logger, logging.lvlError, ex.msg)
    if resp == "":
      case action.kind:
      of Stop:
        break
      of Log:
        logging.log(logger, logging.lvlError, action.message)
      of InsertPost:
        try:
          {.cast(gcsafe).}:
            insertPost(server, action.board, action.post)
        except Exception as ex:
          resp = ex.msg
      of EditPost:
        try:
          {.cast(gcsafe).}:
            editPost(server, action.board, action.content, action.key)
        except Exception as ex:
          resp = ex.msg
      of EditTags:
        try:
          {.cast(gcsafe).}:
            editTags(server, action.board, action.tags, action.tagsSigLast, action.key)
        except Exception as ex:
          resp = ex.msg
    if resp == "" and  action.board != "" and action.key != "":
      try:
        let bbsGitDir = os.absolutePath(server.staticFileDir / paths.boardsDir / action.board)
        if server.useGit:
          discard osproc.execProcess("git", bbsGitDir, args=["add", "."], options={osproc.poStdErrToStdOut, osproc.poUsePath})
          discard osproc.execProcess("git", bbsGitDir, args=["commit", "-m", action.key], options={osproc.poStdErrToStdOut, osproc.poUsePath})
        if server.outDir != "":
          discard osproc.execProcess("git", bbsGitDir, args=["push", "out", "master"], options={osproc.poStdErrToStdOut, osproc.poUsePath})
      except Exception as ex:
        logging.log(logger, logging.lvlError, ex.msg)
    action.error[].send(resp)

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

