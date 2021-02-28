import threadpool, net, os, selectors, strutils

type
  Server = ref object of RootObj
    socket: Socket

const content = "Hello, world!"
const response = "HTTP/1.1 200 OK\r\LContent-Length: " & $content.len & "\r\L\r\L" & content

proc handle(client: Socket) =
  var buf = TaintedString""
  try:
    client.readLine(buf, timeout = 20000)
    client.send(response)
  finally:
    client.close()

proc loop(server: Server, fromClient, fromServer: var Channel[bool]) =
  var selector = newSelector[int]()
  selector.registerHandle(server.socket.getFD, {Event.Read}, 0)
  fromServer.send(true)
  while not fromClient.tryRecv().dataAvailable:
    if selector.select(1000).len > 0:
      var client: Socket = Socket()
      accept(server.socket, client)
      spawn handle(client)

proc listen(server: Server, port: int, fromClient, fromServer: var Channel[bool]) =
  server.socket = newSocket()
  try:
    server.socket.bindAddr(port = Port(port))
    server.socket.listen()
    echo("Server listening on port " & $port)
    server.loop(fromClient, fromServer)
  finally:
    server.socket.close()

proc run*(port: int, fromClient, fromServer: var Channel[bool]) =
  var server = Server()
  server.listen(port, fromClient, fromServer)
