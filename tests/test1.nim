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
    expect client.ClientException:
      client.login(wrongClient)
    expect client.ClientException:
      client.register(wrongClient)
  finally:
    server.stop(s)

test "Room already exists":
  var s = server.initServer("localhost", port)
  server.start(s)
  try:
    var c = client.initClient(config)
    client.register(c)
    client.login(c)
    client.create(c)
    expect client.ClientException:
      client.create(c)
  finally:
    server.stop(s)

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  server.start(s)
  try:
    var c = client.initClient(config)
    client.register(c)
    client.login(c)
    client.create(c)
    client.join(c)
    client.send(c, "Hello, world!")
    echo client.getMessages(c, client.sync(c))
  finally:
    server.stop(s)
