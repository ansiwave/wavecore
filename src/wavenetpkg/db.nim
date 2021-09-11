import sqlite3
from db_sqlite import sql, SqlQuery

proc init*(conn: PSqlite3) =
  # recommended by https://litestream.io/tips/
  db_sqlite.exec conn, sql"""
  PRAGMA journal_mode = WAL;
  PRAGMA busy_timeout = 5000;
  PRAGMA synchronous = NORMAL;
  """

  db_sqlite.exec conn, sql"""
  CREATE TABLE entity (
    id           INTEGER NOT NULL PRIMARY KEY,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  db_sqlite.exec conn, sql"""
  CREATE TABLE value (
    id           INTEGER NOT NULL PRIMARY KEY,
    attribute    TEXT NOT NULL,
    value        TEXT NOT NULL,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    entity_id    INTEGER NOT NULL,
    FOREIGN KEY(entity_id) REFERENCES entity(id)
  )"""

  db_sqlite.exec conn, sql"""
  CREATE INDEX attribute_index ON value (attribute);
  """

proc dbFormat(formatstr: SqlQuery, args: varargs[string]): string =
  result = ""
  var a = 0
  for c in items(string(formatstr)):
    if c == '?':
      add(result, db_sqlite.dbQuote(args[a]))
      inc(a)
    else:
      add(result, c)

proc setupQuery(db: PSqlite3, query: SqlQuery,
                args: varargs[string]): PStmt =
  assert(not db.isNil, "Database not connected.")
  var q = dbFormat(query, args)
  if prepare_v2(db, q, q.len.cint, result, nil) != SQLITE_OK: db_sqlite.dbError(db)

iterator select*[T](db: PSqlite3, ctor: proc (x: var T, stmt: PStmt, col: int32), query: SqlQuery, args: varargs[string, `$`]): T =
  var stmt = setupQuery(db, query, args)
  var obj: T
  try:
    while step(stmt) == SQLITE_ROW:
      var cols = column_count(stmt)
      for col in 0 .. cols-1:
        ctor(obj, stmt, col)
      yield obj
  finally:
    if finalize(stmt) != SQLITE_OK: db_sqlite.dbError(db)

proc insert*[T](conn: PSqlite3, values: T): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  db_sqlite.exec(conn, sql"INSERT INTO entity DEFAULT VALUES")
  result = sqlite3.last_insert_rowid(conn)
  for k, v in values.fieldPairs:
    when k != "id":
      db_sqlite.exec(conn, sql"INSERT INTO value (attribute, value, entity_id) VALUES (?, ?, ?)", k, v, result)
  db_sqlite.exec(conn, sql"COMMIT")
