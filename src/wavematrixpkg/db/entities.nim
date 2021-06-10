import sqlite3
from db_sqlite import sql
from wavematrixpkg/server import nil
from wavematrixpkg/db import nil

proc initAccount(account: var server.Account, stmt: PStmt, col: int32) =
  let colName = $sqlite3.column_name(stmt, col)
  case colName:
  of "id":
    account.id = sqlite3.column_int(stmt, col)
  of "username":
    account.username = $sqlite3.column_text(stmt, col)
  of "password":
    account.password = $sqlite3.column_text(stmt, col)

proc selectAccount*(conn: PSqlite3, username: string): server.Account =
  for x in db.select[server.Account](conn, initAccount,
      sql"""
        SELECT entity.id, value1.value AS username, value2.value AS password FROM entity
        INNER JOIN value as value1 ON value1.entity_id = entity.id
        INNER JOIN value as value2 ON value2.entity_id = entity.id
        WHERE value1.attribute = 'username' AND
              value1.value = ? AND
              value2.attribute = 'password'
        LIMIT 1
      """,
      username
    ):
    return x
