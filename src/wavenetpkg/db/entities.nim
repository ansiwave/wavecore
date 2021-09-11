import sqlite3
from db_sqlite import sql
from wavenetpkg/db import nil

type
  Account* = object
    id*: int64
    username*: string
    public_key*: string

proc initAccount(account: var Account, stmt: PStmt, col: int32) =
  let colName = $sqlite3.column_name(stmt, col)
  case colName:
  of "id":
    account.id = sqlite3.column_int(stmt, col)
  of "username":
    account.username = $sqlite3.column_text(stmt, col)
  of "public_key":
    account.public_key = $sqlite3.column_text(stmt, col)

proc selectAccount*(conn: PSqlite3, username: string): Account =
#[
  for x in db_sqlite.fastRows(conn, sql"""
        EXPLAIN QUERY PLAN SELECT entity.id, value1.value AS username, value2.value AS public_key FROM entity
        INNER JOIN value as value1 ON value1.entity_id = entity.id
        INNER JOIN value as value2 ON value2.entity_id = entity.id
        WHERE value1.attribute = 'username' AND
              value1.value = ? AND
              value2.attribute = 'public_key'
        LIMIT 1
      """, username):
    echo x
]#
  for x in db.select[Account](conn, initAccount,
      sql"""
        SELECT entity.id, value1.value AS username, value2.value AS public_key FROM entity
        INNER JOIN value as value1 ON value1.entity_id = entity.id
        INNER JOIN value as value2 ON value2.entity_id = entity.id
        WHERE value1.attribute = 'username' AND
              value1.value = ? AND
              value2.attribute = 'public_key'
        LIMIT 1
      """,
      username
    ):
    return x
