import sqlite3
from db_sqlite import sql
from wavecorepkg/db import nil

type
  User* = object
    id*: int64
    username*: string
    public_key*: string

proc initUser(account: var User, stmt: PStmt, col: int32) =
  let colName = $sqlite3.column_name(stmt, col)
  case colName:
  of "entity_id":
    account.id = sqlite3.column_int(stmt, col)
  of "username":
    account.username = $sqlite3.column_text(stmt, col)
  of "public_key":
    account.public_key = $sqlite3.column_text(stmt, col)

proc selectUser*(conn: PSqlite3, username: string): User =
  const query =
    """
      SELECT user.entity_id, user.value_indexed AS username, user2.value_indexed AS public_key FROM user
      INNER JOIN user as user2 ON user2.entity_id = user.entity_id
      WHERE user.attribute MATCH 'username' AND
            user.value_indexed MATCH ? AND
            user2.attribute MATCH 'public_key'
      LIMIT 1
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), username):
  #  echo x
  for x in db.select[User](conn, initUser, sql query, username):
    return x

proc insertUser*(conn: PSqlite3, values: User): int64 =
  db.insert(conn, "user", values)

