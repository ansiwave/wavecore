import unittest
import json
from wavenetpkg/client import nil
from wavenetpkg/server import nil
from sugar import nil

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
    let sentMessages = @["Hello, world!", "What's up?"]
    for msg in sentMessages:
      client.send(c, msg)
    let recvMessages = sugar.collect(newSeq):
      for msg in client.getMessages(c, client.sync(c)):
        msg.body
    check sentMessages == recvMessages
  finally:
    server.stop(s)

import wavenetpkg/db
import wavenetpkg/db/entities
from db_sqlite import nil

test "db stuff":
  let conn = db_sqlite.open(":memory:", "", "", "")
  db.init(conn)
  discard db.insert(conn, Account(username: "Alice", public_key: "stuff"))
  discard db.insert(conn, Account(username: "Bob", public_key: "asdf"))
  echo entities.selectAccount(conn, "Alice")
  echo entities.selectAccount(conn, "Bob")
  db_sqlite.close(conn)

