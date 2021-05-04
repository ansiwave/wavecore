import threadpool, net, os, selectors, strutils

type
  Server* = ref object of RootObj
    port: int
    socket: Socket
    fromClient, fromServer: ptr Channel[bool]

proc initServer*(port: int): Server =
  Server(port: port)

const content = "Hello, world!"
const response = "HTTP/1.1 200 OK\r\LContent-Length: " & $content.len & "\r\L\r\L" & content

proc handle(client: Socket) =
  var buf = TaintedString""
  try:
    client.readLine(buf, timeout = 20000)
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
