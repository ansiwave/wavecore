import sqlite3
from db_sqlite import sql, SqlQuery
import tables

type
  Attr = object
    id: int64
    attribute: string
    created_ts: string
  Person* = object
    id*: int64
    name*: string
    age*: int64

var attrs: Table[string, Attr]

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

proc setObject[T](stmt: PStmt, e: var T) =
  var cols = column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $column_name(stmt, col)
    when T is Attr:
      case colName:
      of "id":
        e.id = column_int64(stmt, col)
      of "attribute":
        e.attribute = $column_text(stmt, col)
      of "created_ts":
        e.created_ts = $column_text(stmt, col)
    elif T is Person:
      case colName:
      of "id":
        e.id = column_int64(stmt, col)
      of "name":
        e.name = $column_text(stmt, col)
      of "age":
        e.age = column_int64(stmt, col)

iterator select*[T](db: PSqlite3, query: SqlQuery, args: varargs[string, `$`]): T =
  var stmt = setupQuery(db, query, args)
  var obj: T
  try:
    while step(stmt) == SQLITE_ROW:
      setObject(stmt, obj)
      yield obj
  finally:
    if finalize(stmt) != SQLITE_OK: db_sqlite.dbError(db)

proc init*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
  CREATE TABLE entity (
    id           INTEGER NOT NULL PRIMARY KEY,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  db_sqlite.exec conn, sql"""
  CREATE TABLE attribute (
    id           INTEGER NOT NULL PRIMARY KEY,
    attribute    TEXT NOT NULL UNIQUE,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  db_sqlite.exec conn, sql"""
  CREATE TABLE value (
    id                 INTEGER NOT NULL PRIMARY KEY,
    value              TEXT NOT NULL,
    created_ts         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    entity_id          INTEGER NOT NULL,
    attribute_id       INTEGER NOT NULL,
    FOREIGN KEY(entity_id) REFERENCES entity(id),
    FOREIGN KEY(attribute_id) REFERENCES attribute(id)
  )"""

  db_sqlite.exec(conn, sql"INSERT INTO attribute (attribute) VALUES (?)", "name")
  db_sqlite.exec(conn, sql"INSERT INTO attribute (attribute) VALUES (?)", "age")
  for attr in select[Attr](conn, sql"SELECT * from attribute"):
    attrs[attr.attribute] = attr

proc insert*(conn: PSqlite3, values: Table[string, string]): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  db_sqlite.exec(conn, sql"INSERT INTO entity DEFAULT VALUES")
  result = sqlite3.last_insert_rowid(conn)
  for k, v in values.pairs:
    var args: seq[string]
    args.add(v)
    args.add($result)
    args.add($attrs[k].id)
    db_sqlite.exec(conn, sql"INSERT INTO value (value, entity_id, attribute_id) VALUES (?, ?, ?)", args)
  db_sqlite.exec(conn, sql"COMMIT")
