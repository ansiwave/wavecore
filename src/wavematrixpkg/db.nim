import sqlite3
from db_sqlite import sql, SqlQuery

type
  Entity = object
    id: int64
    created_ts: string

proc initTables*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
  CREATE TABLE entity (
    id           INTEGER NOT NULL PRIMARY KEY,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  db_sqlite.exec conn, sql"""
  CREATE TABLE entity_attr (
    id           INTEGER NOT NULL PRIMARY KEY,
    attr         TEXT NOT NULL,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  db_sqlite.exec conn, sql"""
  CREATE TABLE entity_value (
    id                 INTEGER NOT NULL PRIMARY KEY,
    value              TEXT NOT NULL,
    created_ts         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    entity_id          INTEGER NOT NULL,
    entity_attr_id     INTEGER NOT NULL,
    FOREIGN KEY(entity_id) REFERENCES entity(id),
    FOREIGN KEY(entity_attr_id) REFERENCES entity_attr(id)
  )"""

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

proc setEntity(stmt: PStmt, e: var Entity) =
  var cols = column_count(stmt)
  for col in 0'i32..cols-1:
    let name = $column_name(stmt, col)
    case name:
    of "id":
      e.id = column_int64(stmt, col)
    of "created_ts":
      e.created_ts = $column_text(stmt, col)

iterator selectEntities*(db: PSqlite3, query: SqlQuery,
                         args: varargs[string, `$`]): Entity =
  var stmt = setupQuery(db, query, args)
  var entity: Entity
  try:
    while step(stmt) == SQLITE_ROW:
      setEntity(stmt, entity)
      yield entity
  finally:
    if finalize(stmt) != SQLITE_OK: db_sqlite.dbError(db)

proc insertEntity*(conn: PSqlite3): int64 =
  db_sqlite.exec(conn, sql"INSERT INTO entity DEFAULT VALUES")
  sqlite3.last_insert_rowid(conn)
