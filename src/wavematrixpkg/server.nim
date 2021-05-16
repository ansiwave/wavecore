import threadpool, net, os, selectors, tables
from uri import `$`
from strutils import nil
from parseutils import nil
import httpcore
import json
from oids import nil

type
  Account = object
    username: string
    password: string
    token: string
  State = object
    accounts: Table[string, Account] # username -> Account
    tokens: Table[string, string] # access_token -> username
  StateActionKind = enum
    Register, Login,
  StateAction = object
    case kind: StateActionKind
    of Register, Login:
      account: Account
      token: string
    done: ptr Channel[bool]
  Server* = ref object
    hostname: string
    port: int
    socket: Socket
    listenThread: Thread[Server]
    listenStopped, listenReady: ptr Channel[bool]
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
  selectTimeout = 100
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
    let account = Account(username: body["username"].str, password: body["password"].str, token: initToken())
    sendStateAction(server, StateAction(kind: Register, account: account))
    $ %*{"home_server": server.hostname, "user_id": "@" & account.username & ":" & server.hostname, "access_token": account.token}
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
    var account = server.state[].accounts.getOrDefault(user, Account(username: ""))
    if account.username == "" or account.password != password:
      raise newException(ForbiddenException, "user or password is invalid")
    account.token = initToken()
    sendStateAction(server, StateAction(kind: Login, account: account))
    $ %*{"home_server": server.hostname, "user_id": "@" & account.username & ":" & server.hostname, "access_token": account.token}
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

proc updateState(server: Server, action: StateAction) =
  case action.kind:
  of Register:
    if not server.state[].accounts.hasKey(action.account.username):
      echo "Registering " & $action.account
      server.state[].accounts[action.account.username] = action.account
      server.state[].tokens[action.account.token] = action.account.username
  of Login:
    echo "Logging in " & $action.account
    server.state[].accounts[action.account.username] = action.account
    server.state[].tokens[action.account.token] = action.account.username
    # if already logged in, delete existing token
    if server.state[].accounts.hasKey(action.account.username):
      server.state[].tokens.del(server.state[].accounts[action.account.username].token)
  action.done[].send(true)

proc loop(server: Server) =
  var selector = newSelector[int]()
  selector.registerHandle(server.socket.getFD, {Event.Read}, 0)
  server.listenReady[].send(true)
  while not server.listenStopped[].tryRecv().dataAvailable:
    if selector.select(selectTimeout).len > 0:
      var client: Socket = Socket()
      accept(server.socket, client)
      spawn handle(server, client)
    let res = server.stateAction[].tryRecv()
    if res.dataAvailable:
      updateState(server, res.msg)

proc listen(server: Server) =
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

proc initShared(server: var Server) =
  server.listenStopped = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.listenReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.stateAction = cast[ptr Channel[StateAction]](
    allocShared0(sizeof(Channel[StateAction]))
  )
  server.listenStopped[].open()
  server.listenReady[].open()
  server.stateAction[].open()
  server.state = cast[ptr State](
    allocShared0(sizeof(State))
  )

proc deinitShared(server: var Server) =
  server.listenStopped[].close()
  server.listenReady[].close()
  server.stateAction[].close()
  deallocShared(server.listenStopped)
  deallocShared(server.listenReady)
  deallocShared(server.stateAction)
  deallocShared(server.state)

proc start*(server: var Server) =
  initShared(server)
  proc listenProc(server: Server) {.thread.} =
    server.listen()
  createThread(server.listenThread, listenProc, server)
  discard server.listenReady[].recv() # wait for server to be listenReady

proc stop*(server: var Server) =
  server.listenStopped[].send(true)
  server.listenThread.joinThread()
  deinitShared(server)
