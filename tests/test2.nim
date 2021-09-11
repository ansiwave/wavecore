import unittest
import wavenetpkg/db
import wavenetpkg/db/entities
from db_sqlite import nil
from os import nil
from osproc import nil
from puppy import nil

test "create accounts":
  let conn = db_sqlite.open(":memory:", "", "", "")
  db.init(conn)
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
  try:
    let conn = db_sqlite.open(filename, "", "", "")
    db.init(conn)
    var
      alice = Account(username: "Alice", public_key: "stuff")
      bob = Account(username: "Bob", public_key: "asdf")
    discard db.insert(conn, alice)
    discard db.insert(conn, bob)
    db_sqlite.close(conn)
    let process = osproc.startProcess("ruby", args=["-run", "-ehttpd", ".", "-p" & port], options={osproc.poUsePath, osproc.poStdErrToStdOut})
    os.sleep(1000)
    let res = puppy.fetch(puppy.Request(
      url: puppy.parseUrl("http://localhost:" & port & "/" & filename),
      verb: "get",
      headers: @[puppy.Header(key: "Range", value: "bytes=0-255")]
    ))
    check 206 == res.code
    check 256 == res.body.len
    osproc.kill(process)
  finally:
    os.removeFile(filename)

