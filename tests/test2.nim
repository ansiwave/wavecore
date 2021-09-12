import unittest
import wavenetpkg/db
import wavenetpkg/db/entities
from db_sqlite import nil
from os import nil
from osproc import nil

test "create accounts":
  let conn = db_sqlite.open(":memory:", "", "", "")
  db.init(conn, enableWal = false)
  var
    alice = Account(username: "Alice", public_key: "stuff")
    bob = Account(username: "Bob", public_key: "asdf")
  alice.id = db.insert(conn, alice)
  bob.id = db.insert(conn, bob)
  check alice == entities.selectAccount(conn, "Alice")
  check bob == entities.selectAccount(conn, "Bob")
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
    var conn = db_sqlite.open(filename, "", "", "")
    db.init(conn, enableWal = false)
    var
      alice = Account(username: "Alice", public_key: "stuff")
      bob = Account(username: "Bob", public_key: "asdf")
    discard db.insert(conn, alice)
    discard db.insert(conn, bob)
    db_sqlite.close(conn)
    # re-open db, but this time all reads happen over http
    db.readUrl = "http://localhost:" & port & "/" & filename
    conn = db_sqlite.open(filename, "", "", "")
    let
      alice2 = entities.selectAccount(conn, "Alice")
      bob2 = entities.selectAccount(conn, "Bob")
    alice.id = alice2.id
    bob.id = bob2.id
    check alice == alice2
    check bob == bob2
    db_sqlite.close(conn)
  finally:
    osproc.kill(process)
    os.removeFile(filename)
    db.readUrl = ""

