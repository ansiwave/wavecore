{.passC: "-DSQLITE_ENABLE_FTS5".}

import ./db/sqlite3
from ./db/db_sqlite import sql
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

template withOpen*(conn: untyped, filename: string, http: bool, body: untyped) =
  block:
    let conn = open(filename, http)
    try:
      body
    finally:
      db_sqlite.close(conn)

template withTransaction*(conn: PSqlite3, body: untyped) =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  body
  db_sqlite.exec(conn, sql"COMMIT")

template withStatement*(conn: PSqlite3, query: string, stmt: PStmt, body: untyped) =
  try:
    if prepare_v2(conn, query, query.len.cint, stmt, nil) != SQLITE_OK:
      db_sqlite.dbError(conn)
    body
  finally:
    if finalize(stmt) != SQLITE_OK:
      db_sqlite.dbError(conn)

proc select*[T](conn: PSqlite3, init: proc (stmt: PStmt): T, query: string, args: varargs[string, `$`]): seq[T] =
  var stmt: PStmt
  withStatement(conn, query, stmt):
    for i in 0 ..< args.len:
      db_sqlite.bindParam(db_sqlite.SqlPrepared(stmt), i+1, args[i])
    while step(stmt) == SQLITE_ROW:
      result.add(init(stmt))

proc init*(conn: PSqlite3) =
  var version =
    select[tuple[version: int]](
      conn,
      proc (stmt: PStmt): tuple[version: int] =
        var cols = sqlite3.column_count(stmt)
        for col in 0 .. cols-1:
          let colName = $sqlite3.column_name(stmt, col)
          case colName:
          of "user_version":
            result.version = sqlite3.column_int(stmt, col)
      ,
      "PRAGMA user_version"
    )[0].version
  withTransaction(conn):
    if version == 0:
      db_sqlite.exec conn, sql"""
        CREATE TABLE user (
          user_id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER,
          public_key TEXT UNIQUE,
          public_key_algo TEXT,
          tags TEXT,
          tags_sig TEXT UNIQUE,
          misc TEXT
        ) STRICT
      """
      db_sqlite.exec conn, sql"CREATE INDEX user__ts ON user(ts)"
      db_sqlite.exec conn, sql"CREATE INDEX user__public_key__ts ON user(public_key, ts)"
      db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE user_search USING fts5 (user_id, attribute, value, value_unindexed UNINDEXED)"
      db_sqlite.exec conn, sql"""
        CREATE TABLE post (
          post_id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER,
          content_sig TEXT UNIQUE,
          content_sig_last TEXT UNIQUE,
          public_key TEXT,
          parent TEXT,
          parent_public_key TEXT,
          reply_count INTEGER,
          score INTEGER,
          visibility INTEGER,
          tags TEXT,
          misc TEXT
        ) STRICT
      """
      db_sqlite.exec conn, sql"CREATE INDEX post__ts ON post(ts)"
      db_sqlite.exec conn, sql"CREATE INDEX post__public_key__ts ON post(public_key, ts)"
      db_sqlite.exec conn, sql"CREATE INDEX post__visibility__ts ON post(visibility, ts)"
      db_sqlite.exec conn, sql"CREATE INDEX post__visibility__parent__ts ON post(visibility, parent, ts)"
      db_sqlite.exec conn, sql"CREATE INDEX post__visibility__parent__score ON post(visibility, parent, score)"
      db_sqlite.exec conn, sql"CREATE INDEX post__visibility__public_key__parent__ts ON post(visibility, public_key, parent, ts)"
      db_sqlite.exec conn, sql"CREATE INDEX post__visibility__parent__public_key__ts ON post(visibility, parent_public_key, ts)"
      db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE post_search USING fts5 (post_id, user_id, attribute, value, value_unindexed UNINDEXED)"
      version += 1
      db_sqlite.exec conn, sql("PRAGMA user_version = " & $version)

