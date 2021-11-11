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
    blob*: ed25519.PublicKey
  Signature* = object
    base58*: string
    blob*: ed25519.Signature
  Content* = object
    value*: CompressedValue
    sig*: Signature
  User* = object
    user_id*: int64
    content*: Content
    public_key*: PublicKey
  Post* = object
    post_id*: int64
    content*: Content
    user_id*: int64
    parent_ids*: string
    parent*: string
    reply_count*: int64

proc initCompressedValue*(uncompressed: string): CompressedValue =
  result.compressed = zippy.compress(uncompressed, dataFormat = zippy.dfZlib)
  result.uncompressed = uncompressed

proc initPublicKey*(blob: ed25519.PublicKey): PublicKey =
  result.base58 = base58.encode(blob)
  result.blob = blob

proc initSignature*(blob: ed25519.Signature): Signature =
  result.base58 = base58.encode(blob)
  result.blob = blob

proc initContent*(keys: ed25519.KeyPair, content: string): Content =
  result.value = initCompressedValue(content)
  result.sig = initSignature(ed25519.sign(keys, content))

proc initUser(stmt: PStmt): User =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "user_id":
      result.user_id = sqlite3.column_int(stmt, col)
    of "content":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressed, compressedLen)
        result.content.value = CompressedValue(compressed: cast[string](s), uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "content_sig":
      result.content.sig.base58 = $sqlite3.column_text(stmt, col)
    of "content_sig_blob":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      var sig: ed25519.Signature
      assert compressedLen == sig.len
      copyMem(sig[0].addr, compressed, compressedLen)
      result.content.sig.blob = sig
    of "public_key":
      result.public_key.base58 = $sqlite3.column_text(stmt, col)
    of "public_key_blob":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      var pubkey: ed25519.PublicKey
      assert compressedLen == pubkey.len
      copyMem(pubkey.addr, compressed, compressedLen)
      result.publicKey.blob = pubkey

proc selectUser*(conn: PSqlite3, publicKey: string): User =
  const query =
    """
      SELECT user_id, content, content_sig, content_sig_blob, public_key, public_key_blob FROM user
      WHERE public_key = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  db.select[User](conn, initUser, query, publicKey)[0]

proc insertUser*(conn: PSqlite3, entity: User, extraFn: proc (x: var User, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var e = entity
  var stmt: PStmt
  db.withStatement(conn, "INSERT INTO user (content, content_sig, content_sig_blob, public_key, public_key_blob, public_key_algo) VALUES (?, ?, ?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), entity.content.value.compressed, entity.content.sig.base58, entity.content.sig.blob, entity.publicKey.base58, entity.publicKey.blob, "ed25519")
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    result = sqlite3.last_insert_rowid(conn)
  db.withStatement(conn, "INSERT INTO user_search (user_id, attribute, value) VALUES (?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), result, "content", entity.content.value.uncompressed)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  if extraFn != nil:
    extraFn(e, result)
  db_sqlite.exec(conn, sql"COMMIT")

proc initPost(stmt: PStmt): Post =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "post_id":
      result.post_id = sqlite3.column_int(stmt, col)
    of "user_id":
      result.user_id = sqlite3.column_int(stmt, col)
    of "content":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressed, compressedLen)
        result.content.value = CompressedValue(compressed: cast[string](s), uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "content_sig":
      result.content.sig.base58 = $sqlite3.column_text(stmt, col)
    of "content_sig_blob":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      var sig: ed25519.Signature
      assert compressedLen == sig.len
      copyMem(sig[0].addr, compressed, compressedLen)
      result.content.sig.blob = sig
    of "parent_ids":
      result.parent_ids = $sqlite3.column_text(stmt, col)
    of "parent":
      result.parent = $sqlite3.column_text(stmt, col)
    of "reply_count":
      result.reply_count = sqlite3.column_int(stmt, col)
    else:
      discard

proc selectPost*(conn: PSqlite3, sig: string): Post =
  const query =
    """
      SELECT post_id, content, content_sig, content_sig_blob, user_id, parent, reply_count FROM post
      WHERE content_sig = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  db.select[Post](conn, initPost, query, sig)[0]

proc selectPostParentIds(conn: PSqlite3, id: int64): string =
  const query =
    """
      SELECT parent_ids FROM post
      WHERE post_id = ?
    """
  db.select[Post](conn, initPost, query, id)[0].parent_ids

proc selectPostChildren*(conn: PSqlite3, sig: string): seq[Post] =
  const query =
    """
      SELECT post_id, content, content_sig, content_sig_blob, user_id, parent, reply_count FROM post
      WHERE parent = ?
      ORDER BY score DESC
      LIMIT 10
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, sig))

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: var Post, id: int64) = nil): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  var
    e = entity
    parentId = 0'i64
  if e.parent != "":
    # set the parent ids
    let
      parent = selectPost(conn, e.parent)
      parents = selectPostParentIds(conn, parent.post_id)
    parentId = parent.post_id
    e.parent_ids =
      if parents.len == 0:
        $parentId
      else:
        parents & ", " & $parentId
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
  db.withStatement(conn, "INSERT INTO post (content, content_sig, content_sig_blob, user_id, parent_id, parent_ids, parent, reply_count, score) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), e.content.value.compressed, e.content.sig.base58, e.content.sig.blob, e.user_id, parentId, e.parent_ids, e.parent)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    result = sqlite3.last_insert_rowid(conn)
  db.withStatement(conn, "INSERT INTO post_search (post_id, attribute, value) VALUES (?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), result, "content", e.content.value.uncompressed)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  if extraFn != nil:
    extraFn(e, result)
  db_sqlite.exec(conn, sql"COMMIT")

proc searchPosts*(conn: PSqlite3, term: string): seq[Post] =
  const query =
    """
      SELECT post_id, content, content_sig, content_sig_blob, user_id, parent, reply_count FROM post
      WHERE post_id IN (SELECT post_id FROM post_search WHERE attribute MATCH 'content' AND value MATCH ? ORDER BY rank)
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, term))

