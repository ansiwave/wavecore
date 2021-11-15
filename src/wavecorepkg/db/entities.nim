import ./sqlite3
from ./db_sqlite import sql
from ../db import nil
from zippy import nil
from sequtils import nil
from strutils import format
from ../ed25519 import nil
from base64 import nil

type
  CompressedValue* = object
    compressed*: string
    uncompressed*: string
  Content* = object
    value*: CompressedValue
    sig*: string
  User* = object
    content*: Content
    public_key*: string
  Post* = object
    content*: Content
    public_key*: string
    parent*: string
    reply_count*: int64

proc initCompressedValue*(uncompressed: string): CompressedValue =
  result.compressed = zippy.compress(uncompressed, dataFormat = zippy.dfZlib)
  result.uncompressed = uncompressed

proc initPublicKey*(blob: ed25519.PublicKey): string =
  base64.encode(blob, safe = true)

proc initSignature*(blob: ed25519.Signature): string =
  base64.encode(blob, safe = true)

proc initContent*(keys: ed25519.KeyPair, content: string): Content =
  result.value = initCompressedValue(content)
  result.sig = initSignature(ed25519.sign(keys, content))

proc initUser(stmt: PStmt): User =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "content":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressed, compressedLen)
        result.content.value = CompressedValue(compressed: cast[string](s), uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "content_sig":
      result.content.sig = $sqlite3.column_text(stmt, col)
    of "public_key":
      result.public_key = $sqlite3.column_text(stmt, col)

proc selectUser*(conn: PSqlite3, publicKey: string): User =
  const query =
    """
      SELECT content, content_sig, public_key FROM user
      WHERE public_key = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  db.select[User](conn, initUser, query, publicKey)[0]

proc insertUser*(conn: PSqlite3, entity: User, extraFn: proc (x: var User, id: int64) = nil) =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var
    e = entity
    stmt: PStmt
    id: int64
  db.withStatement(conn, "INSERT INTO user (content, content_sig, public_key, public_key_algo) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), entity.content.value.compressed, entity.content.sig, entity.publicKey, "ed25519")
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    id = sqlite3.last_insert_rowid(conn)
  db.withStatement(conn, "INSERT INTO user_search (user_id, attribute, value) VALUES (?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, "content", entity.content.value.uncompressed)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  if extraFn != nil:
    extraFn(e, id)
  db_sqlite.exec(conn, sql"COMMIT")

proc initPost(stmt: PStmt): Post =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "content":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressed, compressedLen)
        result.content.value = CompressedValue(compressed: cast[string](s), uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "content_sig":
      result.content.sig = $sqlite3.column_text(stmt, col)
    of "public_key":
      result.public_key = $sqlite3.column_text(stmt, col)
    of "parent":
      result.parent = $sqlite3.column_text(stmt, col)
    of "reply_count":
      result.reply_count = sqlite3.column_int(stmt, col)
    else:
      discard

proc selectPost*(conn: PSqlite3, sig: string): Post =
  const query =
    """
      SELECT content, content_sig, public_key, parent, reply_count FROM post
      WHERE content_sig = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  db.select[Post](conn, initPost, query, sig)[0]

proc selectPostExtras*(conn: PSqlite3, sig: string): tuple =
  const query =
    """
      SELECT post_id, score FROM post
      WHERE content_sig = ?
    """
  proc init(stmt: PStmt): tuple =
    var cols = sqlite3.column_count(stmt)
    for col in 0 .. cols-1:
      let colName = $sqlite3.column_name(stmt, col)
      case colName:
      of "post_id":
        result.post_id = sqlite3.column_int(stmt, col)
      of "score":
        result.score = sqlite3.column_int(stmt, col)
  db.select[tuple[post_id: int64, score: int64]](conn, init, query, sig)[0]

proc selectUserExtras*(conn: PSqlite3, publicKey: string): tuple =
  const query =
    """
      SELECT user_id FROM user
      WHERE public_key = ?
    """
  proc init(stmt: PStmt): tuple =
    var cols = sqlite3.column_count(stmt)
    for col in 0 .. cols-1:
      let colName = $sqlite3.column_name(stmt, col)
      case colName:
      of "user_id":
        result.user_id = sqlite3.column_int(stmt, col)
  db.select[tuple[user_id: int64]](conn, init, query, publicKey)[0]

proc selectPostParentIds(conn: PSqlite3, id: int64): string =
  const query =
    """
      SELECT value AS parent_ids FROM post_search
      WHERE post_id MATCH ? AND attribute MATCH 'parent_ids'
    """
  proc init(stmt: PStmt): tuple[parent_ids: string] =
    var cols = sqlite3.column_count(stmt)
    for col in 0 .. cols-1:
      let colName = $sqlite3.column_name(stmt, col)
      case colName:
      of "parent_ids":
        result.parent_ids = $sqlite3.column_text(stmt, col)
  db.select[tuple[parent_ids: string]](conn, init, query, id)[0].parent_ids

proc selectPostChildren*(conn: PSqlite3, sig: string): seq[Post] =
  const query =
    """
      SELECT content, content_sig, public_key, parent, reply_count FROM post
      WHERE parent = ?
      ORDER BY score DESC
      LIMIT 10
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, sig))

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: var Post, id: int64) = nil) =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var
    e = entity
    stmt: PStmt
    id: int64
  let
    parentIds =
      if e.parent == "":
        ""
      else:
        # set the parent ids
        let
          parentId = selectPostExtras(conn, e.parent).post_id
          parentParentIds = selectPostParentIds(conn, parentId)
        if parentParentIds.len == 0:
          $parentId
        else:
          parentParentIds & ", " & $parentId
    parentPublicKey =
      if e.parent == e.public_key:
        e.public_key
      elif e.parent != "":
        selectPost(conn, e.parent).public_key
      else:
        "" # only the root post can have an empty parent
  db.withStatement(conn, "INSERT INTO post (content, content_sig, content_sig_last, public_key, parent, parent_public_key, reply_count, score) VALUES (?, ?, ?, ?, ?, ?, 0, 0)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), e.content.value.compressed, e.content.sig, e.content.sig, e.public_key, e.parent, parentPublicKey)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    id = sqlite3.last_insert_rowid(conn)
  let userId = selectUserExtras(conn, e.public_key).user_id
  db.withStatement(conn, "INSERT INTO post_search (post_id, user_id, attribute, value) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, userId, "content", e.content.value.uncompressed)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  db.withStatement(conn, "INSERT INTO post_search (post_id, user_id, attribute, value) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, userId, "parent_ids", parentIds)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  if e.parent != "":
    # update the parents' reply count and score
    let reply_count_query =
      """
      UPDATE post
      SET reply_count = reply_count + 1
      WHERE post_id IN ($1)
      """.format(parentIds)
    db_sqlite.exec(conn, sql reply_count_query)
    let score_query =
      """
      UPDATE post
      SET score = (SELECT COUNT(DISTINCT user_id) FROM post_search WHERE attribute MATCH 'parent_ids' AND value MATCH post.post_id)
      WHERE post_id IN ($1)
      """.format(parentIds)
    db_sqlite.exec(conn, sql score_query)
  if extraFn != nil:
    extraFn(e, id)
  db_sqlite.exec(conn, sql"COMMIT")

proc searchPosts*(conn: PSqlite3, term: string): seq[Post] =
  const query =
    """
      SELECT content, content_sig, public_key, parent, reply_count FROM post
      WHERE post_id IN (SELECT post_id FROM post_search WHERE attribute MATCH 'content' AND value MATCH ? ORDER BY rank)
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, term))

