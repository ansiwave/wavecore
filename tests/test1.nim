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
import wavematrixpkg/db
import tables

test "db stuff":
  let conn = db_sqlite.open(":memory:", "", "", "")
  db.init(conn)
  discard db.insert(conn, {"name": "Alice", "age": $20}.toTable)
  discard db.insert(conn, {"name": "Bob", "age": $30}.toTable)
  for x in db.select[Person](conn, sql"""
      SELECT entity.id, value1.value AS name, value2.value AS age FROM entity
      INNER JOIN value as value1 ON value1.entity_id = entity.id
      INNER JOIN attribute as attr1 ON attr1.id = value1.attribute_id
      INNER JOIN value as value2 ON value2.entity_id = entity.id
      INNER JOIN attribute as attr2 ON attr2.id = value2.attribute_id
      WHERE attr1.attribute = 'name' AND attr2.attribute = 'age'
    """):
    echo x
  db_sqlite.close(conn)

