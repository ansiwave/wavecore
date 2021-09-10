import unittest
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

