import threadpool, net, os, selectors
from uri import `$`
from strutils import format
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
from times import nil

type
  ListenActionKind {.pure.} = enum
    Stop,
  ListenAction = object
    case kind: ListenActionKind
    of ListenActionKind.Stop:
      discard
  StateActionKind {.pure.} = enum
    Stop, Log, InsertPost, EditPost, EditTags,
  StateAction = object
    case kind: StateActionKind
    of StateActionKind.Stop:
      discard
    of StateActionKind.Log:
      message: string
    of StateActionKind.InsertPost:
      post: entities.Post
    of StateActionKind.EditPost:
      content: entities.Content
    of StateActionKind.EditTags:
      tags: entities.Tags
      tagsSigLast: string
    board: string
    key: string
    error: ptr Channel[string]
  BackgroundActionKind {.pure.} = enum
    Stop, CopyOut,
  BackgroundAction = object
    case kind: BackgroundActionKind
    of BackgroundActionKind.Stop:
      discard
    of BackgroundActionKind.CopyOut:
      board: string
  ServerDetails = tuple
    hostname: string
    port: int
    staticFileDir: string
    options: Table[string, string]
    shouldClone: bool
  ThreadData = tuple
    details: ServerDetails
    readyChan: ptr Channel[bool]
    listenAction: ptr Channel[ListenAction]
    stateAction: ptr Channel[StateAction]
    backgroundAction: ptr Channel[BackgroundAction]
  Server* = object
    details*: ServerDetails
    listenThread: Thread[ThreadData]
    listenReady: ptr Channel[bool]
    listenAction: ptr Channel[ListenAction]
    stateThread: Thread[ThreadData]
    stateAction: ptr Channel[StateAction]
    stateReady: ptr Channel[bool]
    backgroundThread: Thread[ThreadData]
    backgroundReady: ptr Channel[bool]
    backgroundAction: ptr Channel[BackgroundAction]
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

proc initServer*(hostname: string, port: int, staticFileDir: string = "", options: Table[string, string] = initTable[string, string]()): Server =
  Server(details: (hostname: hostname, port: port, staticFileDir: staticFileDir, options: options, shouldClone: "clone" in options))

proc insertPost*(details: ServerDetails, board: string, entity: entities.Post) =
  db.withOpen(conn, details.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      # if user doesn't exist in db, insert it
      try:
        discard entities.selectUser(conn, entity.public_key)
      except Exception as ex:
        entities.insertUser(conn, entities.User(public_key: entity.public_key))
      let sig = entities.insertPost(conn, entity)
      writeFile(details.staticFileDir / paths.ansiwavez(board, sig), entity.content.value.compressed)

proc editPost*(details: ServerDetails, board: string, content: entities.Content, key: string) =
  db.withOpen(conn, details.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      # if user doesn't exist in db, insert it
      try:
        discard entities.selectUser(conn, key)
      except Exception as ex:
        entities.insertUser(conn, entities.User(public_key: key))
      let sig = entities.editPost(conn, content, key)
      writeFile(details.staticFileDir / paths.ansiwavez(board, sig), content.value.compressed)

proc editTags*(details: ServerDetails, board: string, tags: entities.Tags, tagsSigLast: string, key: string) =
  db.withOpen(conn, details.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      entities.editTags(conn, tags, tagsSigLast, board, key)

proc sendAction[T](actionChan: ptr Channel[T], action: T): string =
  let error = cast[ptr Channel[string]](
    allocShared0(sizeof(Channel[string]))
  )
  error[].open()
  var newAction = action
  newAction.error = error
  actionChan[].send(newAction)
  result = error[].recv()
  error[].close()
  deallocShared(error)

proc ansiwavePost(data: ThreadData, request: Request, headers: var string, body: var string) =
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
  if not os.dirExists(data.details.staticFileDir / paths.boardsDir / board):
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
      error = sendAction(data.stateAction, StateAction(kind: InsertPost, board: board, post: post, key: keyBase64))
    if error != "":
      raise newException(Exception, error)
  of "edit":
    let
      content = entities.Content(value: entities.initCompressedValue(request.body), sig: sigBase64, sig_last: cmds["/target"])
      error = sendAction(data.stateAction, StateAction(kind: EditPost, board: board, content: content, key: keyBase64))
    if error != "":
      raise newException(Exception, error)
  of "tags":
    let
      tags = entities.Tags(value: request.body, sig: sigBase64)
      error = sendAction(data.stateAction, StateAction(kind: EditTags, board: board, tags: tags, tagsSigLast: cmds["/target"], key: keyBase64))
    if error != "":
      raise newException(Exception, error)
  else:
    raise newException(BadRequestException, "Invalid /type")

  body = ""
  headers = "HTTP/1.1 200 OK\r\LContent-Length: " & $body.len

proc handleStatic(details: ServerDetails, request: Request, headers: var string, body: var string): bool =
  var filePath = ""
  if request.reqMethod == httpcore.HttpGet and details.staticFileDir != "":
    let path = details.staticFileDir / $request.uri
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

proc handle(data: ThreadData, client: Socket) =
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
      ansiwavePost(data, request, headers, body)
    else:
      when not defined(release):
        if not handleStatic(data.details, request, headers, body):
          raise newException(NotFoundException, "Unhandled request: " & $dispatch)
      else:
        raise newException(NotFoundException, "Unhandled request: " & $dispatch)
  except BadRequestException as ex:
    headers = "HTTP/1.1 400 Bad Request"
    body = ex.msg
    discard sendAction(data.stateAction, StateAction(kind: Log, message: headers & " - " & body))
  except ForbiddenException as ex:
    headers = "HTTP/1.1 403 Forbidden"
    body = ex.msg
    discard sendAction(data.stateAction, StateAction(kind: Log, message: headers & " - " & body))
  except NotFoundException as ex:
    headers = "HTTP/1.1 404 Not Found"
    body = ex.msg
    discard sendAction(data.stateAction, StateAction(kind: Log, message: headers & " - " & body))
  except Exception as ex:
    headers = "HTTP/1.1 500 Internal Server Error"
    body = ex.msg
    discard sendAction(data.stateAction, StateAction(kind: Log, message: headers & " - " & body))
  finally:
    try:
      client.send(headers & "\r\L\r\L" & body)
    except Exception as ex:
      discard
    client.close()

proc loop(data: ThreadData, socket: Socket) =
  var selector = newSelector[int]()
  selector.registerHandle(socket.getFD, {Event.Read}, 0)
  data.readyChan[].send(true)
  while true:
    let (dataAvailable, action) = data.listenAction[].tryRecv()
    if dataAvailable:
      case action.kind:
      of ListenActionKind.Stop:
        break
    elif selector.select(selectTimeout).len > 0:
      var client: Socket = Socket()
      accept(socket, client)
      spawn handle(data, client)

proc listen(data: ThreadData) {.thread.} =
  var socket = newSocket()
  try:
    socket.setSockOpt(OptReuseAddr, true)
    socket.bindAddr(port = Port(data.details.port))
    socket.listen()
    echo("Server listening on port " & $data.details.port)
    loop(data, socket)
  finally:
    echo("Server closing on port " & $data.details.port)
    socket.close()

proc execCmd(command: string) =
  let res = osproc.execCmdEx(command)
  if res.exitCode != 0:
    raise newException(Exception, "Command failed: " & command & "\n" & res.output)

proc recvAction(data: ThreadData) {.thread.} =
  var logger = logging.newConsoleLogger(fmtStr="[$datetime] - $levelname: ")
  data.readyChan[].send(true)
  var
    initializedBoards: HashSet[string]
    keyToLastTs: Table[string, float]
  while true:
    let action = data.stateAction[].recv()
    var resp = ""
    if action.board != "":
      # init board if necessary
      try:
        let bbsGitDir = os.absolutePath(data.details.staticFileDir / paths.boardsDir / action.board)
        os.createDir(bbsGitDir / paths.ansiwavesDir)
        os.createDir(bbsGitDir / paths.dbDir)
        os.createDir(bbsGitDir / paths.miscDir)
        if data.details.shouldClone:
          let outGitDir = os.absolutePath(paths.cloneDir / paths.boardsDir / action.board)
          if not os.dirExists(bbsGitDir / ".git"):
            writeFile(bbsGitDir / ".gitignore", paths.miscDir & "/")
            execCmd("git init $1".format(bbsGitDir))
            execCmd("git -C $1 add .gitignore".format(bbsGitDir))
            execCmd("git -C $1 commit -m \"Add .gitignore\"".format(bbsGitDir))
            logging.log(logger, logging.lvlInfo, "Created " & bbsGitDir)
          if not os.dirExists(bbsGitDir / paths.miscDir / ".git"):
            execCmd("git init $1".format(bbsGitDir / paths.miscDir))
          if not os.dirExists(outGitDir):
            os.createDir(os.parentDir(outGitDir))
            execCmd("git init $1".format(outGitDir))
            execCmd("git -C $1 config --local receive.denyCurrentBranch updateInstead".format(outGitDir))
            logging.log(logger, logging.lvlInfo, "Created " & outGitDir)
          if not os.dirExists(outGitDir / paths.miscDir / ".git"):
            execCmd("git init $1".format(outGitDir / paths.miscDir))
            execCmd("git -C $1 config --local receive.denyCurrentBranch updateInstead".format(outGitDir / paths.miscDir))
        if action.board notin initializedBoards:
          db.withOpen(conn, data.details.staticFileDir / paths.db(action.board), false):
            db.init(conn)
          db.withOpen(conn, data.details.staticFileDir / paths.misc(action.board, paths.purgatoryDb), false):
            db.initMisc(conn)
          db.withOpen(conn, data.details.staticFileDir / paths.misc(action.board, paths.historyDb), false):
            db.initMisc(conn)
          initializedBoards.incl(action.board)
      except Exception as ex:
        resp = "Error initializing board"
        stderr.writeLine(ex.msg)
        stderr.writeLine(getStackTrace(ex))
    if resp == "":
      case action.kind:
      of StateActionKind.Stop:
        break
      of StateActionKind.Log:
        logging.log(logger, logging.lvlError, action.message)
      of StateActionKind.InsertPost:
        try:
          when defined(release):
            if "testrun" notin data.details.options:
              const minInterval = 15
              let ts = times.epochTime()
              if action.key != action.board and action.key in keyToLastTs and ts - keyToLastTs[action.key] < minInterval:
                raise newException(Exception, "Posting too fast! Wait a few seconds.")
              keyToLastTs[action.key] = ts
          {.cast(gcsafe).}:
            insertPost(data.details, action.board, action.post)
        except Exception as ex:
          resp = ex.msg
      of StateActionKind.EditPost:
        try:
          {.cast(gcsafe).}:
            editPost(data.details, action.board, action.content, action.key)
        except Exception as ex:
          resp = ex.msg
      of StateActionKind.EditTags:
        try:
          {.cast(gcsafe).}:
            editTags(data.details, action.board, action.tags, action.tagsSigLast, action.key)
        except Exception as ex:
          resp = ex.msg
    if resp == "" and  action.kind in {StateActionKind.InsertPost, StateActionKind.EditPost, StateActionKind.EditTags}:
      try:
        let bbsGitDir = os.absolutePath(data.details.staticFileDir / paths.boardsDir / action.board)
        if data.details.shouldClone:
          execCmd("git -C $1 add .".format(bbsGitDir))
          execCmd("git -C $1 commit -m \"$2\"".format(bbsGitDir, $action.kind & " " & action.key))
          data.backgroundAction[].send(BackgroundAction(kind: BackgroundActionKind.CopyOut, board: action.board))
      except Exception as ex:
        stderr.writeLine(ex.msg)
        stderr.writeLine(getStackTrace(ex))
    action.error[].send(resp)

proc recvBackgroundAction(data: ThreadData) {.thread.} =
  data.readyChan[].send(true)
  while true:
    let action = data.backgroundAction[].recv()
    case action.kind:
    of BackgroundActionKind.Stop:
      break
    of BackgroundActionKind.CopyOut:
      try:
        let
          bbsGitDir = os.absolutePath(data.details.staticFileDir / paths.boardsDir / action.board)
          outGitDir = os.absolutePath(paths.cloneDir / paths.boardsDir / action.board)
        execCmd("git -C $1 push $2 master".format(bbsGitDir, outGitDir))
      except Exception as ex:
        stderr.writeLine(ex.msg)
        stderr.writeLine(getStackTrace(ex))

proc initShared(server: var Server) =
  # listen
  server.listenReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.listenReady[].open()
  server.listenAction = cast[ptr Channel[ListenAction]](
    allocShared0(sizeof(Channel[ListenAction]))
  )
  server.listenAction[].open()
  # state
  server.stateReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.stateReady[].open()
  server.stateAction = cast[ptr Channel[StateAction]](
    allocShared0(sizeof(Channel[StateAction]))
  )
  server.stateAction[].open()
  # background
  if server.details.shouldClone:
    server.backgroundReady = cast[ptr Channel[bool]](
      allocShared0(sizeof(Channel[bool]))
    )
    server.backgroundReady[].open()
    server.backgroundAction = cast[ptr Channel[BackgroundAction]](
      allocShared0(sizeof(Channel[BackgroundAction]))
    )
    server.backgroundAction[].open()

proc deinitShared(server: var Server) =
  # listen
  server.listenReady[].close()
  deallocShared(server.listenReady)
  server.listenAction[].close()
  deallocShared(server.listenAction)
  # state
  server.stateReady[].close()
  deallocShared(server.stateReady)
  server.stateAction[].close()
  deallocShared(server.stateAction)
  if server.details.shouldClone:
    # background
    server.backgroundReady[].close()
    deallocShared(server.backgroundReady)
    server.backgroundAction[].close()
    deallocShared(server.backgroundAction)

proc initThreads(server: var Server) =
  createThread(server.listenThread, listen, (server.details, server.listenReady, server.listenAction, server.stateAction, server.backgroundAction))
  discard server.listenReady[].recv()
  createThread(server.stateThread, recvAction, (server.details, server.stateReady, server.listenAction, server.stateAction, server.backgroundAction))
  discard server.stateReady[].recv()
  if server.details.shouldClone:
    createThread(server.backgroundThread, recvBackgroundAction, (server.details, server.backgroundReady, server.listenAction, server.stateAction, server.backgroundAction))
    discard server.backgroundReady[].recv()

proc deinitThreads(server: var Server) =
  server.listenAction[].send(ListenAction(kind: ListenActionKind.Stop))
  server.listenThread.joinThread()
  server.stateAction[].send(StateAction(kind: StateActionKind.Stop))
  server.stateThread.joinThread()
  if server.details.shouldClone:
    server.backgroundAction[].send(BackgroundAction(kind: BackgroundActionKind.Stop))
    server.backgroundThread.joinThread()

proc start*(server: var Server) =
  initShared(server)
  initThreads(server)

proc stop*(server: var Server) =
  deinitThreads(server)
  deinitShared(server)

