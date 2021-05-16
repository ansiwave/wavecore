import threadpool, net, os, selectors, tables
from uri import `$`
from strutils import nil
from parseutils import nil
import httpcore
import json

type
  Account = object
    username: string
    password: string
  State = ref object
    accounts: Table[string, Account]
  StateActionKind = enum
    Register,
  StateAction = object
    case kind: StateActionKind
    of Register:
      account: Account
  Server* = ref object
    hostname: string
    port: int
    socket: Socket
    serverStopped, serverReady: ptr Channel[bool]
    stateAction: ptr Channel[StateAction]
    state: State
  Request = object
    uri: uri.Uri
    reqMethod: httpcore.HttpMethod
    headers: httpcore.HttpHeaders
    body: string
  BadRequestException = object of Exception
  NotFoundException = object of Exception

const timeout = 2000

proc initServer*(hostname: string, port: int): Server =
  result = Server(hostname: hostname, port: port)
  new result.state

proc register(server: Server, request: Request): string =
  let body = request.body.parseJson
  if not body.hasKey("auth") or not body["auth"].hasKey("type"):
    raise newException(BadRequestException, "auth required")
  case body["auth"]["type"].str:
  of "m.login.dummy":
    if not body.hasKey("username") or not body.hasKey("password"):
      raise newException(BadRequestException, "username and password required")
    let account = Account(username: body["username"].str, password: body["password"].str)
    server.stateAction[].send(StateAction(kind: Register, account: account))
    # TODO: return access_token
    $ %*{"home_server": server.hostname, "user_id": "@" & account.username & ":" & server.hostname}
  else:
    raise newException(BadRequestException, "Unrecognized auth type")

proc handle(server: Server, client: Socket) =
  try:
    var request = Request(headers: httpcore.newHttpHeaders())
    var firstLine = ""
    client.readLine(firstLine, timeout)
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
      client.readLine(line, timeout)
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
      else:
        raise newException(NotFoundException, "Unhandled request: " & $dispatch)
    client.send("HTTP/1.1 200 OK\r\LContent-Length: " & $response.len & "\r\L\r\L" & response)
  except BadRequestException as ex:
    client.send("HTTP/1.1 400 Bad Request\r\L\r\L" & ex.msg)
  except NotFoundException as ex:
    client.send("HTTP/1.1 404 Not Found\r\L\r\L" & ex.msg)
  finally:
    client.close()

proc updateState(server: Server, action: StateAction) =
  case action.kind:
  of Register:
    if not server.state[].accounts.hasKey(action.account.username):
      echo "Registering " & $action.account
      server.state[].accounts[action.account.username] = action.account

proc loop(server: Server) =
  var selector = newSelector[int]()
  selector.registerHandle(server.socket.getFD, {Event.Read}, 0)
  server.serverReady[].send(true)
  while not server.serverStopped[].tryRecv().dataAvailable:
    if selector.select(1000).len > 0:
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

proc openChannels(server: var Server) =
  server.serverStopped = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.serverReady = cast[ptr Channel[bool]](
    allocShared0(sizeof(Channel[bool]))
  )
  server.stateAction = cast[ptr Channel[StateAction]](
    allocShared0(sizeof(Channel[StateAction]))
  )
  server.serverStopped[].open()
  server.serverReady[].open()
  server.stateAction[].open()

proc closeChannels(server: var Server) =
  server.serverStopped[].close()
  server.serverReady[].close()
  server.stateAction[].close()
  deallocShared(server.serverStopped)
  deallocShared(server.serverReady)
  deallocShared(server.stateAction)

proc start*(server: var Server): Thread[Server] =
  openChannels(server)
  proc listenThread(server: Server) {.thread.} =
    server.listen()
  createThread(result, listenThread, server)
  discard server.serverReady[].recv() # wait for server to be ready

proc stop*(server: var Server, thr: Thread[Server]) =
  server.serverStopped[].send(true)
  thr.joinThread()
  closeChannels(server)
