import ./sqlite3
from ./db_sqlite import sql
from ../db import nil
from zippy import nil
from sequtils import nil
from strutils import format
import json

type
  User* = object
    id*: int64
    username*: string

proc initUser(entity: var User, stmt: PStmt) =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "rowid":
      entity.id = sqlite3.column_int(stmt, col)
    of "username":
      entity.username = $sqlite3.column_text(stmt, col)

proc selectUser*(conn: PSqlite3, username: string): User =
  const query =
    """
      SELECT rowid, json_extract(json, "$.username") AS username FROM user
      WHERE username = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), username):
  #  echo x
  db.select[User](conn, initUser, query, username)[0]

proc insertUser*(conn: PSqlite3, entity: User, extraFn: proc (x: var User, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var e = entity
  if extraFn != nil:
    extraFn(e, result)
  var stmt: PStmt
  const query = "INSERT INTO user (json) VALUES (?)"
  db.withStatement(conn, query, stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), $ %*{"username": e.username})
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    result = sqlite3.last_insert_rowid(conn)
  db_sqlite.exec(conn, sql"COMMIT")

type
  Post* = object
    id*: int64
    parent_id*: int64
    user_id*: int64
    body*: db.CompressedValue
    parent_ids*: string
    reply_count*: int64

proc initPost(entity: var Post, stmt: PStmt) =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "rowid":
      entity.id = sqlite3.column_int(stmt, col)
    of "parent_id":
      entity.parent_id = sqlite3.column_int(stmt, col)
    of "user_id":
      entity.user_id = sqlite3.column_int(stmt, col)
    of "body_compressed":
      let
        compressedBody = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      var s = newSeq[uint8](compressedLen)
      copyMem(s[0].addr, compressedBody, compressedLen)
      entity.body = db.CompressedValue(uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "parent_ids":
      entity.parent_ids = $sqlite3.column_text(stmt, col)
    of "reply_count":
      entity.reply_count = sqlite3.column_int(stmt, col)
    else:
      discard

proc selectPost*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT rowid, body, body_compressed, user_id, parent_id, reply_count FROM post
      WHERE rowid = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  db.select[Post](conn, initPost, query, id)[0]

proc selectPostParentIds*(conn: PSqlite3, id: int64): string =
  const query =
    """
      SELECT parent_ids FROM post
      WHERE rowid = ?
    """
  db.select[Post](conn, initPost, query, id)[0].parent_ids

proc selectPostChildren*(conn: PSqlite3, id: int64): seq[Post] =
  const query =
    """
      SELECT rowid, body, body_compressed, user_id, parent_id, reply_count FROM post
      WHERE parent_id MATCH ? LIMIT 10
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, id))

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: var Post, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var e = entity
  e.body.compressed = cast[seq[uint8]](sequtils.toSeq(zippy.compress(e.body.uncompressed, dataFormat = zippy.dfZlib)))
  if extraFn != nil:
    extraFn(e, result)
  if e.parent_id > 0:
    # set the parent ids
    let parents = selectPostParentIds(conn, e.parent_id)
    e.parent_ids =
      if parents.len == 0:
        $e.parent_id
      else:
        parents & ", " & $e.parent_id
    # update the parents' reply count
    let query =
      """
      UPDATE post
      SET reply_count = reply_count + 1
      WHERE rowid IN ($1)
      """.format(e.parent_ids)
    db_sqlite.exec(conn, sql query)
  var stmt: PStmt
  const query = "INSERT INTO post (body, body_compressed, user_id, parent_id, parent_ids, reply_count) VALUES (?, ?, ?, ?, ?, ?)"
  db.withStatement(conn, query, stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), e.body.uncompressed, e.body.compressed, e.user_id, e.parent_id, e.parent_ids, e.reply_count)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    result = sqlite3.last_insert_rowid(conn)
  db_sqlite.exec(conn, sql"COMMIT")

proc searchPosts*(conn: PSqlite3, term: string): seq[Post] =
  const query =
    """
      SELECT rowid, body, body_compressed, user_id, parent_id, reply_count FROM post
      WHERE body MATCH ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, term))

