import unittest
import json
from wavematrixpkg/client import nil
from wavematrixpkg/server import nil

const
  port = 8008
  config = client.Config(
    username: "user",
    password: "password",
    address: "http://localhost:" & $port,
    server: "localhost",
    room: "stuff",
  )

test "Basic functionality":
  var s = server.initServer(port)
  let thr = server.start(s)
  try:
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
  finally:
    server.stop(s, thr)
