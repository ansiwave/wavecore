import unittest
import wavenetpkg/db
import wavenetpkg/db/entities
from db_sqlite import nil
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

test "retrieve sqlite db via http":
  const
    filename = "test.db"
    port = "8000"
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
    db.withHttp("http://localhost:" & port & "/" & filename):
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

