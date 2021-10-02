{.passC: "-DSQLITE_ENABLE_FTS5".}

import sqlite3
from db_sqlite import sql
from sequtils import nil
from bitops import nil
from db/vfs import nil
import tables

vfs.register()

const
  SQLITE_OPEN_READONLY = 1
  SQLITE_OPEN_READWRITE = 2
  SQLITE_OPEN_CREATE = 4

proc sqlite3_open_v2(filename: cstring, ppDb: var PSqlite3, flags: cint, zVfs: cstring): cint {.cdecl, importc.}

proc open*(filename: string, http: bool = false): PSqlite3 =
  let
    flags: cint = if http: SQLITE_OPEN_READONLY else: bitops.bitor(SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE)
    vfs: cstring = if http: "http".cstring else: nil
  if sqlite3_open_v2(filename, result, flags, vfs) != SQLITE_OK:
    db_sqlite.dbError(result)

proc init*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
  CREATE TABLE entity (
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  # the value_indexed column contains only human-readable text that must be searchable
  # the value_unindexed column contains data that should be excluded from the fts index
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE user USING fts5 (entity_id, attribute, value_indexed, value_unindexed UNINDEXED)"
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE post USING fts5 (entity_id, attribute, value_indexed, value_unindexed UNINDEXED)"

template withStatement(conn: PSqlite3, query: string, stmt: PStmt, body: untyped) =
  try:
    if prepare_v2(conn, query, query.len.cint, stmt, nil) != SQLITE_OK:
      db_sqlite.dbError(conn)
    body
  finally:
    if finalize(stmt) != SQLITE_OK:
      db_sqlite.dbError(conn)

proc select*[T](conn: PSqlite3, setAttr: proc (x: var T, stmt: PStmt, attr: string), query: string, args: varargs[string, `$`]): seq[T] =
  var stmt: PStmt
  var t: OrderedTable[int64, T]
  withStatement(conn, query, stmt):
    for i in 0 ..< args.len:
      db_sqlite.bindParam(db_sqlite.SqlPrepared(stmt), i+1, args[i])
    while step(stmt) == SQLITE_ROW:
      let id = sqlite3.column_int(stmt, 0)
      if not t.hasKey(id):
        t[id] = T(id: id)
      setAttr(t[id], stmt, $sqlite3.column_text(stmt, 1))
  sequtils.toSeq(t.values)

proc insert*[T](conn: PSqlite3, table: static[string], entity: T, extraFn: proc (x: var T, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  db_sqlite.exec(conn, sql"INSERT INTO entity DEFAULT VALUES")
  result = sqlite3.last_insert_rowid(conn)
  var e = entity
  if extraFn != nil:
    extraFn(e, result)
  for k, v in e.fieldPairs:
    when k != "id":
      var stmt: PStmt
      const query = "INSERT INTO " & table & " (entity_id, attribute, value_indexed) VALUES (?, ?, ?)"
      withStatement(conn, query, stmt):
        db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), result, k, v)
        if step(stmt) != SQLITE_DONE:
          db_sqlite.dbError(conn)
  db_sqlite.exec(conn, sql"COMMIT")

