import ./sqlite3
from ./db_sqlite import sql
from ../db import nil
from zippy import nil
from sequtils import nil
from strutils import format
from ../ed25519 import nil
from ../base58 import nil

type
  CompressedValue* = object
    compressed*: string
    uncompressed*: string
  PublicKey* = object
    base58*: string
    raw*: ed25519.PublicKey
  User* = object
    id*: int64
    body*: CompressedValue
    public_key*: PublicKey

proc initCompressedValue*(uncompressed: string): CompressedValue =
  result.compressed = zippy.compress(uncompressed, dataFormat = zippy.dfZlib)
  result.uncompressed = uncompressed

proc initPublicKey*(raw: ed25519.PublicKey): PublicKey =
  result.raw = raw
  result.base58 = base58.encode(raw)

proc initUser(stmt: PStmt): User =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "user_id":
      result.id = sqlite3.column_int(stmt, col)
    of "body":
      let
        compressedBody = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressedBody, compressedLen)
        result.body = CompressedValue(compressed: cast[string](s), uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "public_key":
      result.public_key.base58 = $sqlite3.column_text(stmt, col)
    of "public_key_raw":
      let
        compressedBody = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      var pubkey: ed25519.PublicKey
      assert compressedLen == pubkey.len
      copyMem(pubkey.addr, compressedBody, compressedLen)
      result.publicKey.raw = pubkey

proc selectUser*(conn: PSqlite3, publicKey: string): User =
  const query =
    """
      SELECT user_id, body, public_key, public_key_raw FROM user
      WHERE public_key = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  db.select[User](conn, initUser, query, publicKey)[0]

proc insertUser*(conn: PSqlite3, entity: User, extraFn: proc (x: var User, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var e = entity
  var stmt: PStmt
  db.withStatement(conn, "INSERT INTO user (body, public_key, public_key_raw, public_key_algo) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), entity.body.compressed, entity.publicKey.base58, entity.publicKey.raw, "ed25519")
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    result = sqlite3.last_insert_rowid(conn)
  if extraFn != nil:
    extraFn(e, result)
  db_sqlite.exec(conn, sql"COMMIT")

type
  Post* = object
    id*: int64
    parent_id*: int64
    user_id*: int64
    body*: CompressedValue
    parent_ids*: string
    reply_count*: int64

proc initPost(stmt: PStmt): Post =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "post_id":
      result.id = sqlite3.column_int(stmt, col)
    of "parent_id":
      result.parent_id = sqlite3.column_int(stmt, col)
    of "user_id":
      result.user_id = sqlite3.column_int(stmt, col)
    of "body":
      let
        compressedBody = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressedBody, compressedLen)
        result.body = CompressedValue(compressed: cast[string](s), uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "parent_ids":
      result.parent_ids = $sqlite3.column_text(stmt, col)
    of "reply_count":
      result.reply_count = sqlite3.column_int(stmt, col)
    else:
      discard

proc selectPost*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT post_id, body, user_id, parent_id, reply_count FROM post
      WHERE post_id = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  db.select[Post](conn, initPost, query, id)[0]

proc selectPostParentIds*(conn: PSqlite3, id: int64): string =
  const query =
    """
      SELECT parent_ids FROM post
      WHERE post_id = ?
    """
  db.select[Post](conn, initPost, query, id)[0].parent_ids

proc selectPostChildren*(conn: PSqlite3, id: int64): seq[Post] =
  const query =
    """
      SELECT post_id, body, user_id, parent_id, reply_count FROM post
      WHERE parent_id = ?
      ORDER BY score DESC
      LIMIT 10
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, id))

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: var Post, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var e = entity
  if e.parent_id > 0:
    # set the parent ids
    let parents = selectPostParentIds(conn, e.parent_id)
    e.parent_ids =
      if parents.len == 0:
        $e.parent_id
      else:
        parents & ", " & $e.parent_id
    # update the parents' reply count and score
    let reply_count_query =
      """
      UPDATE post
      SET reply_count = reply_count + 1
      WHERE post_id IN ($1)
      """.format(e.parent_ids)
    db_sqlite.exec(conn, sql reply_count_query)
    let score_query =
      """
      UPDATE post
      SET score = score + 1
      WHERE post_id IN ($1) AND user_id != ?
      """.format(e.parent_ids)
    db_sqlite.exec(conn, sql score_query, e.user_id)
  var stmt: PStmt
  db.withStatement(conn, "INSERT INTO post (body, user_id, parent_id, parent_ids, reply_count, score) VALUES (?, ?, ?, ?, 0, 0)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), e.body.compressed, e.user_id, e.parent_id, e.parent_ids)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    result = sqlite3.last_insert_rowid(conn)
  db.withStatement(conn, "INSERT INTO post_search (post_id, attribute, value) VALUES (?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), result, "body", e.body.uncompressed)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  if extraFn != nil:
    extraFn(e, result)
  db_sqlite.exec(conn, sql"COMMIT")

proc searchPosts*(conn: PSqlite3, term: string): seq[Post] =
  const query =
    """
      SELECT post_id, body, user_id, parent_id, reply_count FROM post
      WHERE post_id IN (SELECT post_id FROM post_search WHERE attribute MATCH 'body' AND value MATCH ?)
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, term))

