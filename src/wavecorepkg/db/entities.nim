import sqlite3
from db_sqlite import sql
from wavecorepkg/db import nil
from zippy import nil
from base64 import nil
from sequtils import nil
from strutils import format

type
  User* = object
    id*: int64
    username*: string
    public_key*: string

proc initUser(entity: var User, stmt: PStmt, col: int32) =
  let colName = $sqlite3.column_name(stmt, col)
  case colName:
  of "entity_id":
    entity.id = sqlite3.column_int(stmt, col)
  of "username":
    entity.username = $sqlite3.column_text(stmt, col)
  of "public_key":
    entity.public_key = $sqlite3.column_text(stmt, col)

proc selectUser*(conn: PSqlite3, username: string): User =
  const query =
    """
      SELECT DISTINCT user.entity_id, user.value_indexed AS username, user_public_key.value_indexed AS public_key FROM user
      INNER JOIN user as user_public_key ON user_public_key.entity_id MATCH user.entity_id
      WHERE user.attribute MATCH 'username' AND
            user.value_indexed MATCH ? AND
            user_public_key.attribute MATCH 'public_key'
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), username):
  #  echo x
  for x in db.select[User](conn, initUser, sql query, username):
    return x

proc insertUser*(conn: PSqlite3, entity: User): int64 =
  db.insert(conn, "user", entity)

type
  Post* = object
    id*: int64
    parent_id*: int64
    user_id*: int64
    body*: db.CompressedValue[string]
    parent_ids*: string
    child_ids*: string

proc initPost(entity: var Post, stmt: PStmt, col: int32) =
  let colName = $sqlite3.column_name(stmt, col)
  case colName:
  of "entity_id":
    entity.id = sqlite3.column_int(stmt, col)
  of "parent_id":
    entity.parent_id = sqlite3.column_int(stmt, col)
  of "user_id":
    entity.user_id = sqlite3.column_int(stmt, col)
  of "body":
    let compressedBody = $sqlite3.column_text(stmt, col)
    entity.body = db.CompressedValue[string](uncompressed: zippy.uncompress(base64.decode(compressedBody), dataFormat = zippy.dfZlib))
  of "parent_ids":
    entity.parent_ids = $sqlite3.column_text(stmt, col)
  of "child_ids":
    entity.child_ids = $sqlite3.column_text(stmt, col)

proc selectPost*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT DISTINCT post.entity_id, post_parent_id.value_indexed AS parent_id, post_user_id.value_indexed AS user_id, post_body.value_unindexed AS body FROM post
      INNER JOIN post as post_parent_id ON post_parent_id.entity_id MATCH post.entity_id
      INNER JOIN post as post_user_id ON post_user_id.entity_id MATCH post.entity_id
      INNER JOIN post as post_body ON post_body.entity_id MATCH post.entity_id
      WHERE post.entity_id MATCH ? AND
            post_parent_id.attribute MATCH 'parent_id' AND
            post_user_id.attribute MATCH 'user_id' AND
            post_body.attribute MATCH 'body'
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  for x in db.select[Post](conn, initPost, sql query, id):
    return x

proc selectPostMetadata*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT DISTINCT post.entity_id, post_parent_ids.value_indexed AS parent_ids, post_child_ids.value_indexed AS child_ids FROM post
      INNER JOIN post as post_parent_ids ON post_parent_ids.entity_id MATCH post.entity_id
      INNER JOIN post as post_child_ids ON post_child_ids.entity_id MATCH post.entity_id
      WHERE post.entity_id MATCH ? AND
            post_parent_ids.attribute MATCH 'parent_ids' AND
            post_child_ids.attribute MATCH 'child_ids'
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  for x in db.select[Post](conn, initPost, sql query, id):
    return x

proc selectPostChildren*(conn: PSqlite3, id: int64): seq[Post] =
  const query =
    """
      SELECT DISTINCT child_post.entity_id, child_post_parent_id.value_indexed AS parent_id, child_post_user_id.value_indexed AS user_id, child_post_body.value_unindexed AS body FROM post
      INNER JOIN post as post_child_ids ON post_child_ids.entity_id MATCH post.entity_id
      INNER JOIN post as child_post ON post_child_ids.value_indexed MATCH child_post.entity_id
      INNER JOIN post as child_post_parent_id ON child_post_parent_id.entity_id MATCH child_post.entity_id
      INNER JOIN post as child_post_user_id ON child_post_user_id.entity_id MATCH child_post.entity_id
      INNER JOIN post as child_post_body ON child_post_body.entity_id MATCH child_post.entity_id
      WHERE post.entity_id MATCH ? AND
            post_child_ids.attribute MATCH 'child_ids' AND
            child_post_parent_id.attribute MATCH 'parent_id' AND
            child_post_user_id.attribute MATCH 'user_id' AND
            child_post_body.attribute MATCH 'body'
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, sql query, id))

proc insertPost*(conn: PSqlite3, entity: Post): int64 =
  var e = entity
  e.body.compressed = base64.encode(zippy.compress(e.body.uncompressed, dataFormat = zippy.dfZlib), safe = true)
  # TODO: strip ANSI codes out of e.body.uncompressed since they don't need to be searchable
  db.insert(conn, "post", e,
    proc (x: var Post, id: int64) =
      if x.parent_id > 0:
        # set the parent ids
        let parents = selectPostMetadata(conn, x.parent_id).parent_ids
        x.parent_ids = parents & " " & $x.parent_id
        # update the parents' child_ids
        let query =
          """
          UPDATE post
          SET value_indexed = value_indexed || ?
          WHERE attribute MATCH 'child_ids' AND
                CAST(entity_id AS INT) IN ($1)
          """.format(strutils.join(strutils.splitWhitespace(x.parent_ids), ", "))
        db_sqlite.exec(conn, sql query, " " & $id)
  )

