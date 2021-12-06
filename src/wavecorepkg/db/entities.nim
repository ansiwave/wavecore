import ./sqlite3
from ./db_sqlite import sql
from ../db import nil
from zippy import nil
from sequtils import nil
from strutils import format
from ../ed25519 import nil
from ../paths import nil
from times import nil
from ../common import nil

type
  CompressedValue* = object
    compressed*: seq[uint8]
    uncompressed*: string
  Content* = object
    value*: CompressedValue
    sig*: string
    sig_last*: string
  User* = object
    user_id*: int64
    public_key*: string
    tags*: string
    tags_sig*: string
  Post* = object
    post_id*: int64
    content*: Content
    public_key*: string
    parent*: string
    reply_count*: int64
    score*: int64
  SearchKind* = enum
    AllPosts, Users,

const limit* = 10

proc initCompressedValue*(uncompressed: string): CompressedValue =
  result.compressed = cast[seq[uint8]](zippy.compress(uncompressed, dataFormat = zippy.dfZlib))
  result.uncompressed = uncompressed

# not used in prod...only in tests
proc initContent*(keys: ed25519.KeyPair, origContent: string): Content =
  let content = "\n\n" & origContent # add two newlines to simulate where headers would've been
  result.value = initCompressedValue(content)
  result.sig = paths.encode(ed25519.sign(keys, content))
  result.sig_last = result.sig

# not used in prod...only in tests
proc initContent*(content: tuple[body: string, sig: string], sigLast: string = content.sig): Content =
  result.value = initCompressedValue(content.body)
  result.sig = content.sig
  result.sig_last = sigLast

proc initPost(stmt: PStmt): Post =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "post_id":
      result.post_id = sqlite3.column_int(stmt, col)
    of "content":
      let
        compressed = sqlite3.column_blob(stmt, col)
        compressedLen = sqlite3.column_bytes(stmt, col)
      if compressedLen > 0:
        var s = newSeq[uint8](compressedLen)
        copyMem(s[0].addr, compressed, compressedLen)
        result.content.value = CompressedValue(compressed: s, uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
    of "content_sig":
      result.content.sig = $sqlite3.column_text(stmt, col)
    of "content_sig_last":
      result.content.sig_last = $sqlite3.column_text(stmt, col)
    of "public_key":
      result.public_key = $sqlite3.column_text(stmt, col)
    of "parent":
      result.parent = $sqlite3.column_text(stmt, col)
    of "reply_count":
      result.reply_count = sqlite3.column_int(stmt, col)
    of "score":
      result.score = sqlite3.column_int(stmt, col)
    else:
      discard

proc selectPost*(conn: PSqlite3, sig: string): Post =
  const query =
    """
      SELECT content, content_sig, content_sig_last, public_key, parent, reply_count FROM post
      WHERE content_sig = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  let ret = db.select[Post](conn, initPost, query, sig)
  if ret.len == 1:
    ret[0]
  else:
    raise newException(Exception, "Can't select post")

proc selectPostExtras*(conn: PSqlite3, sig: string): Post =
  const query =
    """
      SELECT post_id, content, content_sig, content_sig_last, public_key, parent, reply_count, score FROM post
      WHERE content_sig = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  let ret = db.select[Post](conn, initPost, query, sig)
  if ret.len == 1:
    ret[0]
  else:
    raise newException(Exception, "Can't select post")

proc selectPostParentIds(conn: PSqlite3, id: int64): string =
  const query =
    """
      SELECT value AS parentids FROM post_search
      WHERE post_id MATCH ? AND attribute MATCH 'parentids'
    """
  proc init(stmt: PStmt): tuple[parent_ids: string] =
    var cols = sqlite3.column_count(stmt)
    for col in 0 .. cols-1:
      let colName = $sqlite3.column_name(stmt, col)
      case colName:
      of "parentids":
        result.parent_ids = $sqlite3.column_text(stmt, col)
  db.select[tuple[parent_ids: string]](conn, init, query, id)[0].parent_ids

proc selectPostChildren*(conn: PSqlite3, sig: string, sortByTs: bool = false, offset: int = 0): seq[Post] =
  let query =
    """
      SELECT content, content_sig, content_sig_last, public_key, parent, reply_count FROM post
      WHERE parent = ?
      ORDER BY $1 DESC
      LIMIT $2
      OFFSET $3
    """.format((if sortByTs: "ts" else: "score"), limit, offset)
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, sig))

proc selectUserPosts*(conn: PSqlite3, publicKey: string, offset: int = 0): seq[Post] =
  let query =
    """
      SELECT content, content_sig, content_sig_last, public_key, parent, reply_count FROM post
      WHERE public_key = ? AND parent != ''
      ORDER BY ts DESC
      LIMIT $1
      OFFSET $2
    """.format(limit, offset)
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, publicKey))

proc initUser(stmt: PStmt): User =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName
    of "user_id":
      result.user_id = sqlite3.column_int(stmt, col):
    of "public_key":
      result.public_key = $sqlite3.column_text(stmt, col)
    of "tags":
      result.tags = $sqlite3.column_text(stmt, col)
    of "tags_sig":
      result.tags_sig = $sqlite3.column_text(stmt, col)

proc selectUser*(conn: PSqlite3, publicKey: string): User =
  const query =
    """
      SELECT public_key, tags, tags_sig FROM user
      WHERE public_key = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  let ret = db.select[User](conn, initUser, query, publicKey)
  if ret.len == 1:
    ret[0]
  else:
    raise newException(Exception, "Can't select user")

proc selectUserExtras*(conn: PSqlite3, publicKey: string): User =
  const query =
    """
      SELECT user_id, public_key FROM user
      WHERE public_key = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  let ret = db.select[User](conn, initUser, query, publicKey)
  if ret.len == 1:
    ret[0]
  else:
    raise newException(Exception, "Can't select user")

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: Post, sig: string) = nil) =
  var
    e = entity
    stmt: PStmt
    id: int64

  let
    parentIds =
      # top level
      if e.parent == "":
        ""
      # reply to top level
      elif e.parent == e.public_key:
        ""
      else:
        let
          parentId = selectPostExtras(conn, e.parent).post_id
          parentParentIds = selectPostParentIds(conn, parentId)
        if parentParentIds.len == 0:
          $parentId
        else:
          parentParentIds & ", " & $parentId
    parentPublicKey =
      # top level
      if e.parent == "":
        ""
      # reply to top level
      elif e.parent == e.public_key:
        e.public_key
      else:
        let parentPost = selectPost(conn, e.parent)
        # posts that reply to a top level post (i.e. a user's banner)
        # may only come from the user themself.
        # they would've hit the second branch in this conditional
        # so at this point we can just throw an exception if necessary.
        if parentPost.parent == "":
          raise newException(Exception, "Posting here is not allowed")
        parentPost.public_key
    # posts without a parent are considered "top level" (their sig is the user's public key)
    sig =
      if e.parent == "":
        e.public_key
      else:
        e.content.sig

  db.withStatement(conn, "INSERT INTO post (ts, content, content_sig, content_sig_last, public_key, parent, parent_public_key, reply_count, score) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), times.toUnix(times.getTime()), e.content.value.compressed, sig, e.content.sig, e.public_key, e.parent, parentPublicKey)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    id = sqlite3.last_insert_rowid(conn)

  if extraFn != nil:
    extraFn(e, sig)

  let userId = selectUserExtras(conn, entity.public_key).user_id

  db.withStatement(conn, "INSERT INTO post_search (post_id, user_id, attribute, value) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, userId, "content", common.stripUnsearchableText(e.content.value.uncompressed))
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  db.withStatement(conn, "INSERT INTO post_search (post_id, user_id, attribute, value) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, userId, "parentids", parentIds)
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
      SET score = (SELECT COUNT(DISTINCT user_id) FROM post_search WHERE attribute MATCH 'parentids' AND value MATCH post.post_id)
      WHERE post_id IN ($1)
      """.format(parentIds)
    db_sqlite.exec(conn, sql score_query)

proc search*(conn: PSqlite3, kind: SearchKind, term: string, offset: int = 0): seq[Post] =
  if term == "":
    let query =
      case kind:
      of AllPosts:
        """
          SELECT content, content_sig, content_sig_last, public_key, parent, reply_count FROM post
          ORDER BY ts DESC
          LIMIT $1
          OFFSET $2
        """.format(limit, offset)
      of Users:
        """
          SELECT post.content, user.public_key AS content_sig, user.public_key FROM user
          LEFT JOIN post ON user.public_key = post.content_sig
          ORDER BY user.ts DESC
          LIMIT $1
          OFFSET $2
        """.format(limit, offset)
    #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query)):
    #  echo x
    sequtils.toSeq(db.select[Post](conn, initPost, query))
  else:
    let query =
      """
        SELECT content, content_sig, content_sig_last, public_key, parent, reply_count FROM post
        WHERE post_id IN (SELECT post_id FROM post_search WHERE attribute MATCH 'content' AND value MATCH ? ORDER BY rank)
        $1
        LIMIT $2
        OFFSET $3
      """.format((if kind == AllPosts: "" else: "AND parent = ''"), limit, offset)
    #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
    #  echo x
    sequtils.toSeq(db.select[Post](conn, initPost, query, term))

proc editPost*(conn: PSqlite3, content: Content, key: string, extraFn: proc (x: Post) = nil) =
  var stmt: PStmt

  let sigLast =
    # if the content sig_last is same as the public key, this is the first time they've edited their banner
    # so insert it into the db
    if content.sig_last == key:
      insertPost(conn, Post(content: content, public_key: key))
      content.sig
    else:
      content.sig_last

  proc selectPostByLastSig(conn: PSqlite3, sig: string): Post =
    const query =
      """
        SELECT post_id, content, content_sig, content_sig_last, public_key, parent, reply_count, score FROM post
        WHERE content_sig_last = ?
      """
    let ret = db.select[Post](conn, initPost, query, sig)
    if ret.len == 1:
      ret[0]
    else:
      raise newException(Exception, "Can't edit post (maybe you're editing an old version?)")

  let post = selectPostByLastSig(conn, sigLast)

  if post.public_key != key:
    raise newException(Exception, "Cannot edit this post")

  db.withStatement(conn, "UPDATE post SET content = ?, content_sig_last = ? WHERE post_id = ?", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), content.value.compressed, content.sig, post.post_id)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  db.withStatement(conn, "UPDATE post_search SET value = ? WHERE post_id MATCH ? AND attribute MATCH 'content'", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), common.stripUnsearchableText(content.value.uncompressed), post.post_id)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  if extraFn != nil:
    extraFn(selectPost(conn, post.content.sig))

proc insertUser*(conn: PSqlite3, entity: User, extraFn: proc (x: User) = nil) =
  var
    e = entity
    stmt: PStmt
  db.withStatement(conn, "INSERT INTO user (ts, public_key, public_key_algo) VALUES (?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), times.toUnix(times.getTime()), entity.publicKey, "ed25519")
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  if extraFn != nil:
    extraFn(e)

