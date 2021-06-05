import unittest
import json
from wavematrixpkg/client import nil
from wavematrixpkg/server import nil
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

from db_sqlite import `sql`
from wavematrixpkg/db import nil

test "db stuff":
  let conn = db_sqlite.open(":memory:", "", "", "")
  db.initTables(conn)
  echo db.insertEntity(conn)
  for x in db.selectEntities(conn, sql"SELECT * FROM entity"):
    echo x
  db_sqlite.close(conn)

