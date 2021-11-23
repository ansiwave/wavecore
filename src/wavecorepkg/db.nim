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

proc init*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
    CREATE TABLE user (
      user_id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts DATETIME DEFAULT CURRENT_TIMESTAMP,
      public_key TEXT UNIQUE,
      public_key_algo TEXT
    )
  """
  db_sqlite.exec conn, sql"CREATE INDEX user_public_key ON user(public_key)"
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE user_search USING fts5 (user_id, attribute, value, value_unindexed UNINDEXED)"
  db_sqlite.exec conn, sql"""
    CREATE TABLE post (
      post_id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts DATETIME DEFAULT CURRENT_TIMESTAMP,
      content BLOB,
      content_sig TEXT UNIQUE,
      content_sig_last TEXT UNIQUE,
      public_key TEXT,
      parent TEXT,
      parent_public_key TEXT,
      reply_count INTEGER,
      score INTEGER
    )
  """
  db_sqlite.exec conn, sql"CREATE INDEX post_content_sig ON post(content_sig)"
  db_sqlite.exec conn, sql"CREATE INDEX post_content_sig_last ON post(content_sig_last)"
  db_sqlite.exec conn, sql"CREATE INDEX post_public_key ON post(public_key)"
  db_sqlite.exec conn, sql"CREATE INDEX post_parent ON post(parent)"
  db_sqlite.exec conn, sql"CREATE INDEX post_parent_public_key ON post(parent_public_key)"
  db_sqlite.exec conn, sql"CREATE INDEX post_parent_score ON post(parent, score)"
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE post_search USING fts5 (post_id, user_id, attribute, value, value_unindexed UNINDEXED)"

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

