import threadpool, net, os, selectors, tables
from uri import `$`
from strutils import nil
from httpcore import `[]`, `[]=`

type
  Server* = ref object of RootObj
    port: int
    socket: Socket
    fromClient, fromServer: ptr Channel[bool]
  Request = object
    uri: uri.Uri
    reqMethod: httpcore.HttpMethod
    headers: httpcore.HttpHeaders

proc initServer*(port: int): Server =
  Server(port: port)

proc handle(client: Socket) =
  try:
    var
      request = Request(headers: httpcore.newHttpHeaders())
      lineNum = 0
    while true:
      var buf = TaintedString""
      client.readLine(buf, timeout = 2000)
      if lineNum == 0:
        var i = 0
        for linePart in strutils.split(buf, ' '):
          case i
          of 0:
            case linePart
            of "GET": request.reqMethod = httpcore.HttpGet
            of "POST": request.reqMethod = httpcore.HttpPost
            of "HEAD": request.reqMethod = httpcore.HttpHead
            of "PUT": request.reqMethod = httpcore.HttpPut
            of "DELETE": request.reqMethod = httpcore.HttpDelete
            of "PATCH": request.reqMethod = httpcore.HttpPatch
            of "OPTIONS": request.reqMethod = httpcore.HttpOptions
            of "CONNECT": request.reqMethod = httpcore.HttpConnect
            of "TRACE": request.reqMethod = httpcore.HttpTrace
          of 1:
            request.uri = uri.parseUri(linePart)
          of 2:
            # protocol
            discard
          else:
            discard
          i.inc
      else:
        if buf == "\c\L":
          break
        let (key, value) = httpcore.parseHeader(buf)
        request.headers[key] = value
      lineNum.inc
    echo request
    echo request.headers[]
    const content = "{}"
    const response = "HTTP/1.1 200 OK\r\LContent-Length: " & $content.len & "\r\L\r\L" & content
    client.send(response)
  finally:
    client.close()

proc loop(server: Server) =
  var selector = newSelector[int]()
  selector.registerHandle(server.socket.getFD, {Event.Read}, 0)
  server.fromServer[].send(true)
  while not server.fromClient[].tryRecv().dataAvailable:
    if selector.select(1000).len > 0:
      var client: Socket = Socket()
      accept(server.socket, client)
      spawn handle(client)

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

proc openChannels(): (ptr Channel[bool], ptr Channel[bool]) =
  var
    fromClient = cast[ptr Channel[bool]](
      allocShared0(sizeof(Channel[bool]))
    )
    fromServer = cast[ptr Channel[bool]](
      allocShared0(sizeof(Channel[bool]))
    )
  fromClient[].open()
  fromServer[].open()
  (fromClient, fromServer)

proc closeChannels(fromClient, fromServer: ptr Channel[bool]) =
  fromClient[].close()
  fromServer[].close()
  deallocShared(fromClient)
  deallocShared(fromServer)

proc start*(server: var Server): Thread[Server] =
  let (fromClient, fromServer) = openChannels()
  server.fromClient = fromClient
  server.fromServer = fromServer
  proc threadFunc(server: Server) {.thread.} =
    server.listen()
  createThread(result, threadFunc, server)
  discard server.fromServer[].recv() # wait for server to be ready

proc stop*(server: var Server, thr: Thread[Server]) =
  server.fromClient[].send(true)
  thr.joinThread()
  closeChannels(server.fromClient, server.fromServer)
