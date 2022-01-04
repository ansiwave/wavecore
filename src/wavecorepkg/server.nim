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
      extra: bool
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
  Server(details: (hostname: hostname, port: port, staticFileDir: staticFileDir, options: options, shouldClone: "rclone" in options))

proc insertPost*(details: ServerDetails, board: string, entity: entities.Post) =
  var limbo = false
  # try inserting it into the main db
  db.withOpen(conn, details.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      if not entities.existsUser(conn, entity.public_key):
        # if the user is the sysop, insert it
        if entity.public_key == board or "disable-limbo" in details.options:
          entities.insertUser(conn, entities.User(public_key: entity.public_key, tags: entities.Tags(value: "")))
        else:
          limbo = true
      # if we're not inserting into limbo, insert the post
      if not limbo:
        let sig = entities.insertPost(conn, entity)
        writeFile(details.staticFileDir / paths.ansiwavez(board, sig), entity.content.value.compressed)
  # insert into limbo
  if limbo:
    db.withOpen(conn, details.staticFileDir / paths.db(board, limbo = true), false):
      db.withTransaction(conn):
        if not entities.existsUser(conn, entity.public_key):
          entities.insertUser(conn, entities.User(public_key: entity.public_key, tags: entities.Tags(value: "modlimbo")))
        let sig = entities.insertPost(conn, entity, limbo = true)
        writeFile(details.staticFileDir / paths.ansiwavez(board, sig, limbo = true), entity.content.value.compressed)

proc editPost*(details: ServerDetails, board: string, content: entities.Content, key: string) =
  var limbo = false
  # try inserting it into the main db
  db.withOpen(conn, details.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      if not entities.existsUser(conn, key):
        # if the user is the sysop, insert it
        if key == board or "disable-limbo" in details.options:
          entities.insertUser(conn, entities.User(public_key: key, tags: entities.Tags(value: "")))
        else:
          limbo = true
      # if we're not inserting into limbo, insert the post
      if not limbo:
        let sig = entities.editPost(conn, content, key)
        writeFile(details.staticFileDir / paths.ansiwavez(board, sig), content.value.compressed)
  # insert into limbo
  if limbo:
    db.withOpen(conn, details.staticFileDir / paths.db(board, limbo = true), false):
      db.withTransaction(conn):
        if not entities.existsUser(conn, key):
          entities.insertUser(conn, entities.User(public_key: key, tags: entities.Tags(value: "modlimbo")))
        let sig = entities.editPost(conn, content, key)
        writeFile(details.staticFileDir / paths.ansiwavez(board, sig, limbo = true), content.value.compressed)

proc editTags*(details: ServerDetails, board: string, tags: entities.Tags, tagsSigLast: string, key: string, extra: bool) =
  # if we're editing a user in limbo
  db.withOpen(conn, details.staticFileDir / paths.db(board, limbo = true), false):
    db.withTransaction(conn):
      if entities.existsUser(conn, tagsSigLast):
        let
          content = common.splitAfterHeaders(tags.value)
          newTags = common.parseTags(content[0])
        if "modlimbo" in newTags:
          raise newException(Exception, "You must remove modlimbo tag first")
        else:
          const alias = "board"
          db.attach(conn, details.staticFileDir / paths.db(board), alias)
          entities.insertUser(conn, entities.User(public_key: tagsSigLast, tags: entities.Tags(value: "")), dbPrefix = alias & ".")
          # insert posts into main db
          var offset = 0
          while true:
            let posts = entities.selectAllUserPosts(conn, tagsSigLast, offset)
            if posts.len == 0:
              break
            for post in posts:
              discard entities.insertPost(conn, post, dbPrefix = alias & ".")
            offset += entities.limit
          # move ansiwavez files
          offset = 0
          while true:
            let posts = entities.selectAllUserPosts(conn, tagsSigLast, offset)
            if posts.len == 0:
              break
            for post in posts:
              let
                src = details.staticFileDir / paths.ansiwavez(board, post.content.sig, limbo = true)
                dest = details.staticFileDir / paths.ansiwavez(board, post.content.sig)
              if os.fileExists(src):
                os.moveFile(src, dest)
            offset += entities.limit
          # delete user in limbo db
          entities.deleteUser(conn, tagsSigLast)
  db.withOpen(conn, details.staticFileDir / paths.db(board), false):
    db.withTransaction(conn):
      if extra:
        entities.editExtraTags(conn, tags, tagsSigLast, board, key)
      else:
        var userToPurge: string
        entities.editTags(conn, tags, tagsSigLast, board, key, userToPurge)
        if userToPurge != "":
          # purge this user completely
          var offset = 0
          while true:
            let posts = entities.selectAllUserPosts(conn, userToPurge, offset)
            if posts.len == 0:
              break
            for post in posts:
              os.removeFile(details.staticFileDir / paths.ansiwavez(board, post.content.sig))
            offset += entities.limit
          entities.deleteUser(conn, userToPurge)

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
  of "extra-tags":
    let
      tags = entities.Tags(value: request.body, sig: sigBase64)
      error = sendAction(data.stateAction, StateAction(kind: EditTags, board: board, tags: tags, tagsSigLast: cmds["/target"], key: keyBase64, extra: true))
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
      headers &= "\r\LAccess-Control-Allow-Origin: *"
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

proc execCmd(command: string, silent: bool = false): tuple[output: string, exitCode: int] =
  result = osproc.execCmdEx(command)
  if result.exitCode != 0 and not silent:
    raise newException(Exception, "Command failed: " & command & "\n" & result.output)

proc recvAction(data: ThreadData) {.thread.} =
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
        os.createDir(bbsGitDir / paths.miscDir / paths.limboDir / paths.ansiwavesDir)
        os.createDir(bbsGitDir / paths.miscDir / paths.limboDir / paths.dbDir)
        if data.details.shouldClone:
          let outGitDir = os.absolutePath(paths.cloneDir / paths.boardsDir / action.board)
          if not os.dirExists(bbsGitDir / ".git"):
            writeFile(bbsGitDir / ".gitignore", paths.miscDir & "/")
            discard execCmd("git init $1".format(bbsGitDir))
            discard execCmd("git -C $1 add .gitignore".format(bbsGitDir))
            discard execCmd("git -C $1 commit -m \"Add .gitignore\"".format(bbsGitDir))
          if not os.dirExists(bbsGitDir / paths.miscDir / ".git"):
            writeFile(bbsGitDir / paths.miscDir / ".gitignore", "")
            discard execCmd("git init $1".format(bbsGitDir / paths.miscDir))
            discard execCmd("git -C $1 add .gitignore".format(bbsGitDir / paths.miscDir))
            discard execCmd("git -C $1 commit -m \"Add .gitignore\"".format(bbsGitDir / paths.miscDir))
            echo "Created " & bbsGitDir / paths.miscDir
          if not os.dirExists(outGitDir):
            os.createDir(os.parentDir(outGitDir))
            discard execCmd("git init $1".format(outGitDir))
            discard execCmd("git -C $1 config --local receive.denyCurrentBranch updateInstead".format(outGitDir))
            echo "Created " & outGitDir
          if not os.dirExists(outGitDir / paths.miscDir):
            os.createDir(outGitDir / paths.miscDir)
            discard execCmd("git init $1".format(outGitDir / paths.miscDir))
            discard execCmd("git -C $1 config --local receive.denyCurrentBranch updateInstead".format(outGitDir / paths.miscDir))
            echo "Created " & outGitDir / paths.miscDir
        if action.board notin initializedBoards:
          db.withOpen(conn, data.details.staticFileDir / paths.db(action.board), false):
            db.init(conn)
          db.withOpen(conn, data.details.staticFileDir / paths.db(action.board, limbo = true), false):
            db.init(conn)
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
        echo action.message
      of StateActionKind.InsertPost:
        try:
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
            editTags(data.details, action.board, action.tags, action.tagsSigLast, action.key, action.extra)
        except Exception as ex:
          resp = ex.msg
    if resp == "" and  action.kind in {StateActionKind.InsertPost, StateActionKind.EditPost, StateActionKind.EditTags}:
      try:
        let bbsGitDir = os.absolutePath(data.details.staticFileDir / paths.boardsDir / action.board)
        if data.details.shouldClone:
          discard execCmd("git -C $1 add .".format(bbsGitDir))
          let mainResult = execCmd("git -C $1 commit -m \"$2\"".format(bbsGitDir, $action.kind & " " & action.key), silent = true)
          discard execCmd("git -C $1 add .".format(bbsGitDir / paths.miscDir))
          let miscResult = execCmd("git -C $1 commit -m \"$2\"".format(bbsGitDir / paths.miscDir, $action.kind & " " & action.key), silent = true)
          if mainResult.exitCode != 0 and miscResult.exitCode != 0:
            raise newException(Exception, mainResult.output & "\n" & miscResult.output)
          data.backgroundAction[].send(BackgroundAction(kind: BackgroundActionKind.CopyOut, board: action.board))
      except Exception as ex:
        stderr.writeLine(ex.msg)
        stderr.writeLine(getStackTrace(ex))
    action.error[].send(resp)

proc recvBackgroundAction(data: ThreadData) {.thread.} =
  data.readyChan[].send(true)
  var
    lastClone = 0.0
    lastSync = 0.0
    boardsToCopy: HashSet[string]
    boardsToSync: HashSet[string]
  while true:
    let (dataAvailable, action) = data.backgroundAction[].tryRecv()
    if dataAvailable:
      case action.kind:
      of BackgroundActionKind.Stop:
        break
      of BackgroundActionKind.CopyOut:
        try:
          let
            bbsGitDir = os.absolutePath(data.details.staticFileDir / paths.boardsDir / action.board)
            outGitDir = os.absolutePath(paths.cloneDir / paths.boardsDir / action.board)
          discard execCmd("git -C $1 push $2 master".format(bbsGitDir, outGitDir))
          discard execCmd("git -C $1 push $2 master".format(bbsGitDir / paths.miscDir, outGitDir / paths.miscDir))
          boardsToCopy.incl(action.board)
          boardsToSync.incl(action.board)
        except Exception as ex:
          stderr.writeLine(ex.msg)
          stderr.writeLine(getStackTrace(ex))
    else:
      os.sleep(selectTimeout)
    try:
      if boardsToCopy.len > 0 and times.epochTime() - lastClone >= 15:
        for board in boardsToCopy:
          let outGitDir = os.absolutePath(paths.cloneDir / paths.boardsDir / board)
          let output = execCmd("rclone copy $1 $2/$3/$4/ --exclude .git/ --exclude misc/.git/ --verbose --checksum --no-update-modtime".format(outGitDir, data.details.options["rclone"], paths.boardsDir, board)).output
          discard sendAction(data.stateAction, StateAction(kind: Log, message: "rclone copy output for $1\n$2".format(board, output)))
        boardsToCopy.clear
        lastClone = times.epochTime()
      if boardsToSync.len > 0 and times.epochTime() - lastSync >= 60:
        for board in boardsToSync:
          let outGitDir = os.absolutePath(paths.cloneDir / paths.boardsDir / board)
          discard execCmd("git -C $1 gc".format(outGitDir))
          discard execCmd("git -C $1 update-server-info".format(outGitDir))
          let output = execCmd("rclone sync $1/.git $2/$3/$4/.git --verbose --checksum --no-update-modtime".format(outGitDir, data.details.options["rclone"], paths.boardsDir, board))
          discard sendAction(data.stateAction, StateAction(kind: Log, message: "rclone sync output for $1\n$2".format(board, output)))
        boardsToSync.clear
        lastSync = times.epochTime()
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

