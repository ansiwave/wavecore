import ./sqlite3
from ./db_sqlite import sql
from ../db import nil
from zippy import nil
from sequtils import nil
from strutils import format
from times import nil
from ../common import nil
import sets

type
  CompressedValue* = object
    compressed*: seq[uint8]
    uncompressed*: string
  Content* = object
    value*: CompressedValue
    sig*: string
    sig_last*: string
  Tags* = object
    value*: string
    sig*: string
  User* = object
    user_id*: int64
    public_key*: string
    tags*: Tags
  Post* = object
    post_id*: int64
    ts*: int64
    content*: Content
    public_key*: string
    parent*: string
    reply_count*: int64
    score*: int64
    partition*: int64
    tags*: string
  SearchKind* = enum
    Posts, Users, UserTags,

const limit* = 10

proc initCompressedValue*(uncompressed: string): CompressedValue =
  result.compressed = cast[seq[uint8]](zippy.compress(uncompressed, dataFormat = zippy.dfZlib))
  result.uncompressed = uncompressed

proc initPost(stmt: PStmt): Post =
  var cols = sqlite3.column_count(stmt)
  for col in 0 .. cols-1:
    let colName = $sqlite3.column_name(stmt, col)
    case colName:
    of "post_id":
      result.post_id = sqlite3.column_int(stmt, col)
    of "ts":
      result.ts = sqlite3.column_int(stmt, col)
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
    of "partition":
      result.partition = sqlite3.column_int(stmt, col)
    of "tags":
      result.tags = $sqlite3.column_text(stmt, col)
    else:
      discard

proc selectPost*(conn: PSqlite3, sig: string): Post =
  let query =
    """
      SELECT post_id, ts, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
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
      SELECT post_id, ts, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
      WHERE parent = ? $1
      ORDER BY $2 DESC
      LIMIT $3
      OFFSET $4
    """.format((if sortByTs: "" else: "AND visibility = 1"), (if sortByTs: "ts" else: "score"), limit, offset)
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), sig):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, sig))

proc selectUserPosts*(conn: PSqlite3, publicKey: string, offset: int = 0): seq[Post] =
  let query =
    """
      SELECT post_id, ts, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
      WHERE public_key = ? AND parent != ''
      ORDER BY ts DESC
      LIMIT $1
      OFFSET $2
    """.format(limit, offset)
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, publicKey))

proc selectUserReplies*(conn: PSqlite3, publicKey: string, offset: int = 0): seq[Post] =
  let query =
    """
      SELECT post_id, ts, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
      WHERE visibility = 1 AND parent_public_key = ? AND parent_public_key != public_key
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
      result.tags.value = $sqlite3.column_text(stmt, col)
    of "tags_sig":
      result.tags.sig = $sqlite3.column_text(stmt, col)

proc selectUser*(conn: PSqlite3, publicKey: string): User =
  const query =
    """
      SELECT user_id, public_key, tags, tags_sig FROM user
      WHERE public_key = ?
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), publicKey):
  #  echo x
  let ret = db.select[User](conn, initUser, query, publicKey)
  if ret.len == 1:
    ret[0]
  else:
    raise newException(Exception, "Can't select user")

proc insertPost*(conn: PSqlite3, e: Post, id: var int64): string =
  let sourceUser = selectUser(conn, e.public_key)
  if "modban" in common.parseTags(sourceUser.tags.value):
    raise newException(Exception, "You are banned")

  var stmt: PStmt

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
          parentId = selectPost(conn, e.parent).post_id
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

  let
    visibility = if "modhide" in common.parseTags(sourceUser.tags.value): 0 else: 1
    ts = times.toUnix(times.getTime())

  db.withStatement(conn, "INSERT INTO post (ts, content_sig, content_sig_last, public_key, parent, parent_public_key, reply_count, distinct_reply_count, score, visibility, tags) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), ts, sig, e.content.sig, e.public_key, e.parent, parentPublicKey, visibility, sourceUser.tags.value)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    id = sqlite3.last_insert_rowid(conn)

  let userId = sourceUser.user_id

  db.withStatement(conn, "INSERT INTO post_search (post_id, user_id, attribute, value) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, userId, "content", common.stripUnsearchableText(e.content.value.uncompressed))
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
  db.withStatement(conn, "INSERT INTO post_search (post_id, user_id, attribute, value) VALUES (?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, userId, "parentids", parentIds)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  if e.parent != "":
    # update the partition and score for all sibling posts
    const partitionSize = 60 * 60 * 24 # how many seconds for each partition
    let partitionQuery =
      """
      UPDATE post
      SET partition = 1000000000 - (((? - ts) / ?) * 1000)
      WHERE parent = ?
      """
    db_sqlite.exec(conn, sql partitionQuery, ts, partitionSize, e.parent)
    let scoreQuery =
      """
      UPDATE post
      SET score = partition + distinct_reply_count
      WHERE parent = ?
      """
    db_sqlite.exec(conn, sql scoreQuery, e.parent)

    # update the reply count and score for all parent posts
    let parentReplyCountQuery =
      """
      UPDATE post
      SET
      reply_count = reply_count + 1,
      distinct_reply_count = (
        SELECT COUNT(DISTINCT user_id) FROM post_search
        INNER JOIN post AS child_post ON post_search.post_id = child_post.post_id
        WHERE post_search.attribute MATCH 'parentids' AND post_search.value MATCH post.post_id AND child_post.visibility = 1
      )
      WHERE post_id IN ($1)
      """.format(parentIds)
    db_sqlite.exec(conn, sql parentReplyCountQuery)
    let parentScoreQuery =
      """
      UPDATE post
      SET score = partition + distinct_reply_count
      WHERE post_id IN ($1)
      """.format(parentIds)
    db_sqlite.exec(conn, sql parentScoreQuery)

  return sig

proc insertPost*(conn: PSqlite3, entity: Post): string =
  var id: int64
  insertPost(conn, entity, id)

proc search*(conn: PSqlite3, kind: SearchKind, term: string, offset: int = 0): seq[Post] =
  if term == "":
    let query =
      case kind:
      of Posts:
        """
          SELECT post_id, ts, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
          WHERE parent != '' AND visibility = 1
          ORDER BY ts DESC
          LIMIT $1
          OFFSET $2
        """.format(limit, offset)
      of Users:
        """
          SELECT user.public_key AS content_sig, user.public_key, user.tags FROM user
          WHERE user.tags NOT LIKE "%modhide%"
          ORDER BY user.ts DESC
          LIMIT $1
          OFFSET $2
        """.format(limit, offset)
      of UserTags:
        """
          SELECT user.public_key AS content_sig, user.public_key, user.tags FROM user
          WHERE user.tags NOT LIKE "%modhide%" AND user.tags != ""
          ORDER BY user.ts DESC
          LIMIT $1
          OFFSET $2
        """.format(limit, offset)
    #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query)):
    #  echo x
    sequtils.toSeq(db.select[Post](conn, initPost, query))
  else:
    let query =
      case kind:
      of Posts, Users:
        """
          SELECT post_id, ts, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
          WHERE post_id IN (SELECT post_id FROM post_search WHERE attribute MATCH 'content' AND value MATCH ? ORDER BY rank)
          AND visibility = 1
          AND $1
          LIMIT $2
          OFFSET $3
        """.format((if kind == Posts: "parent != ''" else: "parent = ''"), limit, offset)
      of UserTags:
        """
          SELECT public_key AS content_sig, public_key, tags FROM user
          WHERE user_id IN (SELECT user_id FROM user_search WHERE attribute MATCH 'tags' AND value MATCH ? ORDER BY rank)
          LIMIT $1
          OFFSET $2
        """.format(limit, offset)
    #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
    #  echo x
    sequtils.toSeq(db.select[Post](conn, initPost, query, term))

proc editPost*(conn: PSqlite3, content: Content, key: string): string =
  let sourceUser = selectUser(conn, key)
  if "modban" in common.parseTags(sourceUser.tags.value):
    raise newException(Exception, "You are banned")

  var stmt: PStmt

  let sigLast =
    # if the content sig_last is same as the public key, this is the first time they've edited their banner
    # so insert it into the db
    if content.sig_last == key:
      discard insertPost(conn, Post(content: content, public_key: key))
      content.sig
    else:
      content.sig_last

  proc selectPostByLastSig(conn: PSqlite3, sig: string): Post =
    const query =
      """
        SELECT post_id, content_sig, content_sig_last, public_key, parent, reply_count, score, partition, tags FROM post
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

  db.withStatement(conn, "UPDATE post SET content_sig_last = ? WHERE post_id = ?", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), content.sig, post.post_id)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  db.withStatement(conn, "UPDATE post_search SET value = ? WHERE post_id MATCH ? AND attribute MATCH 'content'", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), common.stripUnsearchableText(content.value.uncompressed), post.post_id)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  return post.content.sig

proc insertUser*(conn: PSqlite3, entity: User, id: var int64) =
  var stmt: PStmt

  db.withStatement(conn, "INSERT INTO user (ts, public_key, public_key_algo, tags, tags_sig) VALUES (?, ?, ?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), times.toUnix(times.getTime()), entity.publicKey, "ed25519", entity.tags.value, entity.publicKey)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)
    id = sqlite3.last_insert_rowid(conn)

  db.withStatement(conn, "INSERT INTO user_search (user_id, attribute, value) VALUES (?, ?, ?)", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), id, "tags", entity.tags.value)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

proc insertUser*(conn: PSqlite3, entity: User) =
  var id: int64
  insertUser(conn, entity, id)

const
  modRoles = ["modleader", "moderator"].toHashSet
  modCommands = modRoles + ["modban", "modhide"].toHashSet

proc editTags*(conn: PSqlite3, tags: Tags, tagsSigLast: string, board: string, key: string) =
  if tagsSigLast == board:
    raise newException(Exception, "Cannot tag the sysop")

  proc selectUserByTagsSigLast(conn: PSqlite3, sig: string): User =
    const query =
      """
        SELECT user_id, public_key, tags, tags_sig FROM user
        WHERE tags_sig = ?
      """
    let ret = db.select[User](conn, initUser, query, sig)
    if ret.len == 1:
      ret[0]
    else:
      raise newException(Exception, "Can't edit tags (maybe you're editing an old version?)")

  let
    targetUser = selectUserByTagsSigLast(conn, tagsSigLast)
    content = common.splitAfterHeaders(tags.value)

  if content.len != 1:
    raise newException(Exception, "Tags must be on a single line")
  elif content[0].len > 80:
    raise newException(Exception, "Max tag length exceeded")

  for ch in content[0]:
    if ch notin {'a'..'z', ' '}:
      raise newException(Exception, "Only the letters a-z are allowed in tags")

  let
    oldTags = common.parseTags(targetUser.tags.value)
    newTags = common.parseTags(content[0])

  for tag in newTags:
    if strutils.startsWith(tag, "mod") and tag notin modCommands:
      raise newException(Exception, tag & " is an invalid tag")

  if key != board:
    let
      sourceUser = selectUser(conn, key)
      sourceTags = common.parseTags(sourceUser.tags.value)
    if "modban" in sourceTags:
      raise newException(Exception, "You are banned")
    if "moderator" notin sourceTags and "modleader" notin sourceTags:
      raise newException(Exception, "Only the sysop or moderators can edit tags")
    let changedTags = oldTags.symmetricDifference(newTags)
    if changedTags - modRoles != changedTags and "modleader" notin sourceTags:
      raise newException(Exception, "Only modleaders can change someone's moderator status")
    if changedTags - modCommands != changedTags and "modleader" in oldTags and "modleader" notin sourceTags:
      raise newException(Exception, "Only modleaders can change mod tags of another modleader")

  var stmt: PStmt

  db.withStatement(conn, "UPDATE user SET tags = ?, tags_sig = ? WHERE user_id = ?", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), content[0], tags.sig, targetUser.user_id)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  db.withStatement(conn, "UPDATE user_search SET value = ? WHERE user_id MATCH ? AND attribute MATCH 'tags'", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), content[0], targetUser.user_id)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  db.withStatement(conn, "UPDATE post SET tags = ? WHERE public_key = ?", stmt):
    db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), content[0], targetUser.public_key)
    if step(stmt) != SQLITE_DONE:
      db_sqlite.dbError(conn)

  if "modhide" in newTags and "modhide" notin oldTags:
    db.withStatement(conn, "UPDATE post SET visibility = ? WHERE public_key = ?", stmt):
      db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), 0, targetUser.public_key)
      if step(stmt) != SQLITE_DONE:
        db_sqlite.dbError(conn)
  elif "modhide" in oldTags and "modhide" notin newTags:
    db.withStatement(conn, "UPDATE post SET visibility = ? WHERE public_key = ?", stmt):
      db_sqlite.bindParams(db_sqlite.SqlPrepared(stmt), 1, targetUser.public_key)
      if step(stmt) != SQLITE_DONE:
        db_sqlite.dbError(conn)

