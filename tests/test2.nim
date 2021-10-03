import unittest
import wavecorepkg/db
import wavecorepkg/db/entities
import wavecorepkg/db/vfs
from wavecorepkg/db/db_sqlite import nil
from os import nil
from osproc import nil

test "create users":
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

test "create posts":
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

test "retrieve sqlite db via http":
  const
    filename = "test.db"
    port = "8000"
  vfs.readUrl = "http://localhost:" & port & "/" & filename
  var process: osproc.Process = nil
  try:
    # start web server
    process = osproc.startProcess("ruby", args=["-run", "-ehttpd", ".", "-p" & port], options={osproc.poUsePath, osproc.poStdErrToStdOut})
    os.sleep(1000)
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
    osproc.kill(process)
    os.removeFile(filename)

