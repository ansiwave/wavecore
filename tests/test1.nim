import unittest
from wavecorepkg/client import nil
from wavecorepkg/server import nil
import json
from puppy import nil

const
  port = 3000
  address = "http://localhost:" & $port

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    discard client.post(c, "test", %* {"success": true})
    expect client.ClientException:
      discard client.post(c, "test", nil)
  finally:
    server.stop(s)
    client.stop(c)

test "Request static file":
  var s = server.initServer("localhost", port, @["tests"])
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    discard client.get(c, "config.nims")
    discard client.get(c, "config.nims", (0, 10))
  finally:
    server.stop(s)
    client.stop(c)

test "Request static file asynchronously":
  var s = server.initServer("localhost", port, @["tests"])
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  let response = cast[ptr Channel[puppy.Response]](
    allocShared0(sizeof(Channel[puppy.Response]))
  )
  response[].open()
  try:
    client.get(c, "config.nims", response)
    discard response[].recv()
  finally:
    response[].close()
    deallocShared(response)
    server.stop(s)
    client.stop(c)

import wavecorepkg/db
import wavecorepkg/db/entities
import wavecorepkg/db/vfs
from wavecorepkg/db/db_sqlite import nil
from os import nil

test "query users":
  let conn = db.open(":memory:")
  db.init(conn)
  var
    alice = User(username: "Alice", public_key: "stuff")
    bob = User(username: "Bob", public_key: "asdf")
  alice.id = entities.insertUser(conn, alice)
  bob.id = entities.insertUser(conn, bob)
  check alice == entities.selectUser(conn, "Alice")
  check bob == entities.selectUser(conn, "Bob")
  db_sqlite.close(conn)

test "query users asynchronously":
  var s = server.initServer("localhost", port, @["."])
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  const filename = "test.db"
  vfs.readUrl = "http://localhost:" & $port & "/" & filename
  try:
    # create test db
    let conn = db.open(filename)
    db.init(conn)
    var
      alice = User(username: "Alice", public_key: "stuff")
      bob = User(username: "Bob", public_key: "asdf")
    alice.id = entities.insertUser(conn, alice)
    bob.id = entities.insertUser(conn, bob)
    db_sqlite.close(conn)
    # query db over http
    let response = client.queryUser(c, filename, "Alice")
    check response[].recv() == alice
    response[].close()
    deallocShared(response)
    let response2 = client.queryUser(c, filename, "Bob")
    check response2[].recv() == bob
    response2[].close()
    deallocShared(response2)
  finally:
    os.removeFile(filename)
    server.stop(s)
    client.stop(c)

test "query posts":
  let conn = db.open(":memory:")
  db.init(conn)
  var
    alice = User(username: "Alice", public_key: "stuff")
    bob = User(username: "Bob", public_key: "asdf")
  alice.id = entities.insertUser(conn, alice)
  bob.id = entities.insertUser(conn, bob)
  var p1 = Post(parent_id: 0, user_id: alice.id, body: "Hello, i'm alice")
  p1.id = entities.insertPost(conn, p1)
  var p2 = Post(parent_id: p1.id, user_id: bob.id, body: "Hello, i'm bob")
  p2.id = entities.insertPost(conn, p2)
  var p3 = Post(parent_id: p2.id, user_id: alice.id, body: "What's up")
  p3.id = entities.insertPost(conn, p3)
  var p4 = Post(parent_id: p2.id, user_id: alice.id, body: "How are you?")
  p4.id = entities.insertPost(conn, p4)
  p1 = entities.selectPost(conn, p1.id)
  p2 = entities.selectPost(conn, p2.id)
  p3 = entities.selectPost(conn, p3.id)
  p4 = entities.selectPost(conn, p4.id)
  check @[p2] == entities.selectPostChildren(conn, p1.id)
  check 3 == entities.selectPost(conn, p1.id).reply_count
  check @[p3, p4] == entities.selectPostChildren(conn, p2.id)
  check 2 == entities.selectPost(conn, p2.id).reply_count
  db_sqlite.close(conn)

test "query posts asynchronously":
  var s = server.initServer("localhost", port, @["."])
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  const filename = "test.db"
  vfs.readUrl = "http://localhost:" & $port & "/" & filename
  try:
    # create test db
    let conn = db.open(filename)
    db.init(conn)
    var
      alice = User(username: "Alice", public_key: "stuff")
      bob = User(username: "Bob", public_key: "asdf")
    alice.id = entities.insertUser(conn, alice)
    bob.id = entities.insertUser(conn, bob)
    var p1 = Post(parent_id: 0, user_id: alice.id, body: "Hello, i'm alice")
    p1.id = entities.insertPost(conn, p1)
    var p2 = Post(parent_id: p1.id, user_id: bob.id, body: "Hello, i'm bob")
    p2.id = entities.insertPost(conn, p2)
    var p3 = Post(parent_id: p2.id, user_id: alice.id, body: "What's up")
    p3.id = entities.insertPost(conn, p3)
    var p4 = Post(parent_id: p2.id, user_id: alice.id, body: "How are you?")
    p4.id = entities.insertPost(conn, p4)
    p1 = entities.selectPost(conn, p1.id)
    db_sqlite.close(conn)
    # query db over http
    let response = client.queryPost(c, filename, p1.id)
    check response[].recv() == p1
    response[].close()
    deallocShared(response)
    let response2 = client.queryPostChildren(c, filename, p2.id)
    check response2[].recv() == @[p3, p4]
    response2[].close()
    deallocShared(response2)
  finally:
    os.removeFile(filename)
    server.stop(s)
    client.stop(c)

test "retrieve sqlite db via http":
  var s = server.initServer("localhost", port, @["."])
  server.start(s)
  const filename = "test.db"
  vfs.readUrl = "http://localhost:" & $port & "/" & filename
  try:
    # create test db
    var conn = db.open(filename)
    db.init(conn)
    var
      alice = User(username: "Alice", public_key: "stuff")
      bob = User(username: "Bob", public_key: "asdf")
    discard entities.insertUser(conn, alice)
    discard entities.insertUser(conn, bob)
    db_sqlite.close(conn)
    # re-open db, but this time all reads happen over http
    conn = db.open(filename, true)
    let
      alice2 = entities.selectUser(conn, "Alice")
      bob2 = entities.selectUser(conn, "Bob")
    alice.id = alice2.id
    bob.id = bob2.id
    check alice == alice2
    check bob == bob2
    db_sqlite.close(conn)
  finally:
    os.removeFile(filename)
    server.stop(s)

