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
  db.readUrl = "http://localhost:" & port & "/"
  var process: osproc.Process = nil
  try:
    # start web server
    process = osproc.startProcess("ruby", args=["-run", "-ehttpd", ".", "-p" & port], options={osproc.poUsePath, osproc.poStdErrToStdOut})
    os.sleep(1000)
    # create test db
    var conn = db.open(filename)
    db.init(conn)
    for i in  0 .. 3000:
      discard entities.insertUser(conn, User(username: "Alice" & $i, public_key: "stuff"))
    check "Alice2000" == entities.selectUser(conn, "Alice2000").username
    db_sqlite.close(conn)
    # re-open db, but this time all reads happen over http
    conn = db.open(filename, true)
    check "Alice2000" == entities.selectUser(conn, "Alice2000").username
    db_sqlite.close(conn)
  finally:
    osproc.kill(process)
    os.removeFile(filename)

