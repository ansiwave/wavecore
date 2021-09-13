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
  of "rowid":
    account.id = sqlite3.column_int(stmt, col)
  of "username":
    account.username = $sqlite3.column_text(stmt, col)
  of "public_key":
    account.public_key = $sqlite3.column_text(stmt, col)

proc selectAccount*(conn: PSqlite3, username: string): Account =
  const query =
    """
      SELECT entity.rowid, attr_value1.value_indexed AS username, attr_value2.value_indexed AS public_key FROM entity
      INNER JOIN attr_value as attr_value1 ON attr_value1.entity_id = entity.rowid
      INNER JOIN attr_value as attr_value2 ON attr_value2.entity_id = entity.rowid
      WHERE attr_value1.attribute MATCH 'username' AND
            attr_value1.value_indexed MATCH ? AND
            attr_value2.attribute MATCH 'public_key'
      LIMIT 1
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), username):
  #  echo x
  for x in db.select[Account](conn, initAccount, sql query, username):
    return x
