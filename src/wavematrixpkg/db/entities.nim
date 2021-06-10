import sqlite3
from db_sqlite import sql, SqlQuery
from wavematrixpkg/server import nil
from wavematrixpkg/db import nil
from sequtils import toSeq

proc initAccount(account: var server.Account, stmt: PStmt, col: int32) =
  let colName = $sqlite3.column_name(stmt, col)
  case colName:
  of "username":
    account.username = $sqlite3.column_text(stmt, col)
  of "password":
    account.password = $sqlite3.column_text(stmt, col)

proc selectAccounts*(conn: PSqlite3): seq[server.Account] =
  db.select[server.Account](conn, initAccount,
    sql"""
      SELECT entity.id, value1.value AS username, value2.value AS password FROM entity
      INNER JOIN value as value1 ON value1.entity_id = entity.id
      INNER JOIN value as value2 ON value2.entity_id = entity.id
      WHERE value1.attribute = 'username' AND value2.attribute = 'password'
    """
  ).toSeq()
