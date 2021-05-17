import unittest
import json
from wavematrixpkg/client import nil
from wavematrixpkg/server import nil

const
  port = 3000
  config = client.Config(
    username: "user",
    password: "password",
    address: "http://localhost:" & $port,
    server: "localhost",
    room: "stuff",
  )

test "Failed login/register":
  var s = server.initServer("localhost", port)
  server.start(s)
  try:
    client.register(client.initClient(config))
    var wrongConfig = config
    wrongConfig.password = "wrong password"
    var wrongClient = client.initClient(wrongConfig)
    expect client.RequestException:
      client.login(wrongClient)
    expect client.RequestException:
      client.register(wrongClient)
  finally:
    server.stop(s)

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  server.start(s)
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
    server.stop(s)
