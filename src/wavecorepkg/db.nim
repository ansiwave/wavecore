{.passC: "-DSQLITE_ENABLE_FTS5".}

import ./db/sqlite3
from ./db/db_sqlite import sql
from sequtils import nil
from bitops import nil
import tables

const
  SQLITE_OPEN_READONLY = 1
  SQLITE_OPEN_READWRITE = 2
  SQLITE_OPEN_CREATE = 4

proc sqlite3_open_v2(filename: cstring, ppDb: var PSqlite3, flags: cint, zVfs: cstring): cint {.cdecl, importc.}

proc open*(filename: string, http: bool = false): PSqlite3 =
  let
    flags: cint = if http: SQLITE_OPEN_READONLY else: bitops.bitor(SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE)
    vfs: cstring = if http: "http".cstring else: "multiplex".cstring
  if sqlite3_open_v2(filename, result, flags, vfs) != SQLITE_OK:
    db_sqlite.dbError(result)

proc init*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
  pragma journal_mode = delete; -- to be able to actually set page size
  pragma page_size = 1024;
  """

  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE user USING fts5 (body, body_compressed UNINDEXED, username)"
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE post USING fts5 (body, body_compressed UNINDEXED, user_id, parent_id, parent_ids UNINDEXED, reply_count UNINDEXED)"

template withStatement*(conn: PSqlite3, query: string, stmt: PStmt, body: untyped) =
  try:
    if prepare_v2(conn, query, query.len.cint, stmt, nil) != SQLITE_OK:
      db_sqlite.dbError(conn)
    body
  finally:
    if finalize(stmt) != SQLITE_OK:
      db_sqlite.dbError(conn)

proc select*[T](conn: PSqlite3, init: proc (x: var T, stmt: PStmt), query: string, args: varargs[string, `$`]): seq[T] =
  var stmt: PStmt
  withStatement(conn, query, stmt):
    for i in 0 ..< args.len:
      db_sqlite.bindParam(db_sqlite.SqlPrepared(stmt), i+1, args[i])
    while step(stmt) == SQLITE_ROW:
      var p: T
      init(p, stmt)
      result.add(p)

type
  CompressedValue* = object
    compressed*: seq[uint8]
    uncompressed*: string

