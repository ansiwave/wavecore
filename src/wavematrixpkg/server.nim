import threadpool, net, os, selectors, tables
from uri import `$`
from strutils import nil
from parseutils import nil
import httpcore
import json
from oids import nil
from times import nil

type
  Account = object
    username: string
    password: string
  AccountPointer = object
    username: string
    timestamp: float
  State = object
    accounts: Table[string, Account] # keys are usernames
    tokens: OrderedTable[string, AccountPointer] # keys are tokens
  StateActionKind = enum
    Stop, Register, Login,
  StateAction = object
    case kind: StateActionKind
    of Stop:
      discard
    of Register, Login:
      account: Account
      token: string
    done: ptr Channel[bool]
  Server* = ref object
    hostname: string
    port: int
    socket: Socket
    listenThread, stateThread: Thread[Server]
    listenStopped, listenReady, stateReady: ptr Channel[bool]
    stateAction: ptr Channel[StateAction]
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

proc initServer*(hostname: string, port: int): Server =
  Server(hostname: hostname, port: port)

proc initToken(): string =
  # TODO: come up with better way of generating tokens
  $abs(oids.hash(oids.genOid()))

proc sendStateAction(server: Server, action: StateAction) =
  let done = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  done[].open()
  var newAction = action
  newAction.done = done
  server.stateAction[].send(newAction)
  discard done[].recv()
  deallocShared(done)

proc register(server: Server, request: Request): string =
  let body = request.body.parseJson
  if not body.hasKey("auth") or not body["auth"].hasKey("type"):
    raise newException(BadRequestException, "auth required")
  case body["auth"]["type"].str:
  of "m.login.dummy":
    if not body.hasKey("username") or not body.hasKey("password"):
      raise newException(BadRequestException, "username and password required")
    let
      username = body["username"].str
      password = body["password"].str
      account = Account(username: username, password: password)
      action = StateAction(kind: Register, account: account, token: initToken())
      existingAccount = server.state[].accounts.getOrDefault(username, Account(username: ""))
    if existingAccount.username == "" or password == existingAccount.password:
      sendStateAction(server, action)
      $ %*{"home_server": server.hostname, "user_id": "@" & account.username & ":" & server.hostname, "access_token": action.token}
    else:
      raise newException(ForbiddenException, "username or password is invalid")
  else:
    raise newException(BadRequestException, "Unrecognized auth type")

proc login(server: Server, request: Request): string =
  let body = request.body.parseJson
  if not body.hasKey("type"):
    raise newException(BadRequestException, "type required")
  case body["type"].str:
  of "m.login.password":
    if not body.hasKey("user") or not body.hasKey("password"):
      raise newException(BadRequestException, "user and password required")
    let
      user = body["user"].str
      password = body["password"].str
    let
      account = server.state[].accounts.getOrDefault(user, Account(username: ""))
      action = StateAction(kind: Login, account: account, token: initToken())
    if account.username == "" or account.password != password:
      raise newException(ForbiddenException, "user or password is invalid")
    sendStateAction(server, action)
    $ %*{"home_server": server.hostname, "user_id": "@" & account.username & ":" & server.hostname, "access_token": action.token}
  else:
    raise newException(BadRequestException, "Unrecognized auth type")

proc handle(server: Server, client: Socket) =
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
    # response
    let dispatch = (request.reqMethod, $request.uri)
    let response =
      if dispatch == (httpcore.HttpPost, "/_matrix/client/r0/register"):
        register(server, request)
      elif dispatch == (httpcore.HttpPost, "/_matrix/client/r0/login"):
        login(server, request)
      else:
        raise newException(NotFoundException, "Unhandled request: " & $dispatch)
    client.send("HTTP/1.1 200 OK\r\LContent-Length: " & $response.len & "\r\L\r\L" & response)
  except BadRequestException as ex:
    client.send("HTTP/1.1 400 Bad Request\r\L\r\L" & ex.msg)
  except ForbiddenException as ex:
    client.send("HTTP/1.1 403 Forbidden\r\L\r\L" & ex.msg)
  except NotFoundException as ex:
    client.send("HTTP/1.1 404 Not Found\r\L\r\L" & ex.msg)
  except Exception as ex:
    client.send("HTTP/1.1 500 Internal Server Error\r\L\r\L" & ex.msg)
  finally:
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

proc recvStateAction(server: Server) {.thread.} =
  server.stateReady[].send(true)
  while true:
    let action = server.stateAction[].recv()
    case action.kind:
    of Stop:
      break
    of Register, Login:
      echo $action.kind & " " & $action.account
      server.state[].accounts[action.account.username] = action.account
      server.state[].tokens[action.token] = AccountPointer(username: action.account.username, timestamp: times.epochTime())
    action.done[].send(true)

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
  server.stateAction = cast[ptr Channel[StateAction]](
    allocShared0(sizeof(Channel[StateAction]))
  )
  server.listenStopped[].open()
  server.listenReady[].open()
  server.stateReady[].open()
  server.stateAction[].open()
  server.state = cast[ptr State](
    allocShared0(sizeof(State))
  )

proc deinitShared(server: var Server) =
  server.listenStopped[].close()
  server.listenReady[].close()
  server.stateReady[].close()
  server.stateAction[].close()
  deallocShared(server.listenStopped)
  deallocShared(server.listenReady)
  deallocShared(server.stateReady)
  deallocShared(server.stateAction)
  deallocShared(server.state)

proc initThreads(server: var Server) =
  createThread(server.listenThread, listen, server)
  createThread(server.stateThread, recvStateAction, server)
  discard server.listenReady[].recv()
  discard server.stateReady[].recv()

proc deinitThreads(server: var Server) =
  server.listenStopped[].send(true)
  server.stateAction[].send(StateAction(kind: Stop))
  server.listenThread.joinThread()
  server.stateThread.joinThread()

proc start*(server: var Server) =
  initShared(server)
  initThreads(server)

proc stop*(server: var Server) =
  deinitThreads(server)
  deinitShared(server)