import unittest
import json
from wavematrix/client import nil
from wavematrix/server import nil

const
  port = 8008
  config = client.Config(
    username: "user",
    password: "password",
    address: "http://localhost:" & $port,
    server: "localhost",
    room: "stuff",
  )

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

proc startServer(fromClient, fromServer: ptr Channel[bool]): Thread[(ptr Channel[bool], ptr Channel[bool])] =
  proc threadFunc(chans: (ptr Channel[bool], ptr Channel[bool])) {.thread.} =
    server.run(port, chans[0][], chans[1][])
  createThread(result, threadFunc, (fromClient, fromServer))
  discard fromServer[].recv() # wait for server to be ready

proc stopServer(fromClient: ptr Channel[bool], thr: Thread[(ptr Channel[bool], ptr Channel[bool])]) =
  fromClient[].send(true)
  thr.joinThread()

test "Start server":
  let
    (fromClient, fromServer) = openChannels()
    thr = startServer(fromClient, fromServer)
  stopServer(fromClient, thr)
  closeChannels(fromClient, fromServer)

test "Basic functionality":
  var c = client.initClient(config)
  client.register(c)
  client.login(c)
  try:
    client.create(c)
  except Exception as e:
    echo e.msg
  client.join(c)
  client.send(c, "Hello, world!")
  echo client.getMessages(c, client.sync(c))
