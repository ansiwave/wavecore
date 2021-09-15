{.passC: "-DSQLITE_ENABLE_FTS5".}
import sqlite3

from db_sqlite import sql, SqlQuery
from puppy import nil

{.passC: "-DSQLITE_MULTIPLEX_CHUNK_SIZE=100000".}
{.compile: "sqlite3_multiplex.c".}

from os import nil

var readUrl*: string

proc httpRead(filename: cstring, chunk: cint, buf: pointer; iAmt: cint; iOfst: int64): cint {.exportc: "httpRead".} =
  assert readUrl != ""
  var url = readUrl & os.splitPath($filename).tail
  if chunk > 0:
    url &= "00" & $chunk
  let res = puppy.fetch(puppy.Request(
    url: puppy.parseUrl(url),
    verb: "get",
    headers: @[puppy.Header(key: "Range", value: "bytes=" & $iOfst & "-" & $(iOfst+iAmt-1))]
  ))
  if res.code == 206:
    assert res.body.len == iAmt
    copyMem(buf, res.body[0].addr, res.body.len)
    SQLITE_OK
  else:
    SQLITE_ERROR

proc writeFileSize(filename: cstring, size: int64) {.exportc: "writeFileSize".} =
  var f: File
  if open(f, $filename & ".size", fmWrite):
    write(f, $size)
    close(f)

from parseutils import nil

proc readFileSize(filename: cstring, size: ptr int64): cint {.exportc: "readFileSize".} =
  assert readUrl != ""
  let url = readUrl & os.splitPath($filename).tail & ".size"
  let res = puppy.fetch(puppy.Request(
    url: puppy.parseUrl(url),
    verb: "get",
  ))
  var i: int
  if res.code == 200 and parseutils.parseInt(res.body, i) > 0:
    size[] = i
    SQLITE_OK
  else:
    SQLITE_ERROR

proc sqlite3_multiplex_initialize(zOrigVfsName: cstring, makeDefault: cint): cint {.cdecl, importc.}
discard sqlite3_multiplex_initialize(nil, 0)

proc sqlite3_open_v2(filename: cstring, ppDb: var PSqlite3, flags: cint, zVfs: cstring): cint {.cdecl, importc.}

const
  SQLITE_OPEN_READONLY = 1
  SQLITE_OPEN_READWRITE = 2
  SQLITE_OPEN_CREATE = 4

import bitops

proc open*(filename: string, readOnly: bool = false): db_sqlite.DbConn =
  var db: db_sqlite.DbConn
  if sqlite3_open_v2(filename, db, if readOnly: SQLITE_OPEN_READONLY else: bitor(SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE), "multiplex") == SQLITE_OK:
    result = db
  else:
    db_sqlite.dbError(db)

proc init*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
  CREATE TABLE entity (
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  # the value_indexed column contains only human-readable text that must be searchable
  # the value_unindexed column contains data that should be excluded from the fts index
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE user USING fts5 (entity_id, attribute, value_indexed, value_unindexed UNINDEXED)"
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE post USING fts5 (entity_id, attribute, value_indexed, value_unindexed UNINDEXED)"

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

proc insert*[T](conn: PSqlite3, table: string, values: T): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  db_sqlite.exec(conn, sql"INSERT INTO entity DEFAULT VALUES")
  result = sqlite3.last_insert_rowid(conn)
  for k, v in values.fieldPairs:
    when k != "id":
      db_sqlite.exec(conn, sql("INSERT INTO " & table & " (entity_id, attribute, value_indexed) VALUES (?, ?, ?)"), result, k, v)
  db_sqlite.exec(conn, sql"COMMIT")
