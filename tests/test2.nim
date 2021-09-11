import unittest
import wavenetpkg/db
import wavenetpkg/db/entities
from db_sqlite import nil

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

