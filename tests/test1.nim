import unittest
import json
from wavematrixpkg/client import nil
from wavematrixpkg/server import nil
from os import nil

const
  port = 3000
  config = client.Config(
    username: "user",
    password: "password",
    address: "http://localhost:" & $port,
    server: "localhost",
    room: "stuff",
  )

test "Failed login":
  var s = server.initServer("localhost", port)
  let thr = server.start(s)
  try:
    client.register(client.initClient(config))
    os.sleep(1000) # TODO: find better way to wait for registration to complete
    var wrongConfig = config
    wrongConfig.password = "wrong password"
    var wrongClient = client.initClient(wrongConfig)
    expect client.RequestException:
      client.login(wrongClient)
  finally:
    server.stop(s, thr)

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  let thr = server.start(s)
  try:
    var c = client.initClient(config)
    client.register(c)
    os.sleep(1000) # TODO: find better way to wait for registration to complete
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
