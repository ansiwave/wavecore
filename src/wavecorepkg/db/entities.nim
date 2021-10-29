import ./sqlite3
from ./db_sqlite import sql
from ../db import nil
from zippy import nil
from sequtils import nil
from strutils import format

type
  User* = object
    id*: int64
    username*: string
    publickey*: string

proc initUser(entity: var User, stmt: PStmt, attr: string) =
  case attr:
  of "username":
    entity.username = $sqlite3.column_text(stmt, 2)
  of "publickey":
    entity.publickey = $sqlite3.column_text(stmt, 2)

proc selectUser*(conn: PSqlite3, username: string): User =
  const query =
    """
      SELECT * FROM user
      WHERE entity_id MATCH (SELECT entity_id FROM user WHERE attribute MATCH 'username' AND value_indexed MATCH ?)
            AND attribute IN ('username', 'publickey')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), username):
  #  echo x
  for x in db.select[User](conn, initUser, query, username):
    return x

proc insertUser*(conn: PSqlite3, entity: User): int64 =
  db.insert(conn, "user", entity)

type
  Post* = object
    id*: int64
    parentid*: int64
    userid*: int64
    body*: db.CompressedValue
    parentids*: string
    replycount*: int64

proc initPost(entity: var Post, stmt: PStmt, attr: string) =
  case attr:
  of "parentid":
    entity.parentid = sqlite3.column_int(stmt, 2)
  of "userid":
    entity.userid = sqlite3.column_int(stmt, 2)
  of "body":
    let
      compressedBody = sqlite3.column_blob(stmt, 3)
      compressedLen = sqlite3.column_bytes(stmt, 3)
    var s = newSeq[uint8](compressedLen)
    copyMem(s[0].addr, compressedBody, compressedLen)
    entity.body = db.CompressedValue(uncompressed: zippy.uncompress(cast[string](s), dataFormat = zippy.dfZlib))
  of "parentids":
    entity.parentids = $sqlite3.column_text(stmt, 2)
  of "replycount":
    entity.replycount = sqlite3.column_int(stmt, 2)

proc selectPost*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id MATCH ?
            AND attribute IN ('parentid', 'userid', 'body', 'replycount')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  db.select[Post](conn, initPost, query, id)[0]

proc selectPostMetadata*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id MATCH ?
            AND attribute IN ('parentids')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  db.select[Post](conn, initPost, query, id)[0]

proc selectPostChildren*(conn: PSqlite3, id: int64): seq[Post] =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id IN (SELECT entity_id FROM post WHERE attribute MATCH 'parentid' AND value_indexed MATCH ? LIMIT 10)
            AND post.attribute IN ('parentid', 'userid', 'body', 'replycount')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, id))

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: var Post, id: int64) = nil): int64 =
  var e = entity
  e.body.compressed = cast[seq[uint8]](sequtils.toSeq(zippy.compress(e.body.uncompressed, dataFormat = zippy.dfZlib)))
  # TODO: strip ANSI codes out of e.body.uncompressed since they don't need to be searchable
  db.insert(conn, "post", e,
    proc (x: var Post, id: int64) =
      if extraFn != nil:
        extraFn(x, id)
      if x.parentid > 0:
        # set the parent ids
        let parents = selectPostMetadata(conn, x.parentid).parentids
        x.parentids =
          if parents.len == 0:
            $x.parentid
          else:
            parents & ", " & $x.parentid
        # update the parents' reply count
        let query =
          """
          UPDATE post
          SET value_indexed = value_indexed + 1
          WHERE attribute MATCH 'replycount' AND
                CAST(entity_id AS INT) IN ($2)
          """.format(id, x.parentids)
        db_sqlite.exec(conn, sql query)
  )

proc searchPosts*(conn: PSqlite3, term: string): seq[Post] =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id IN (SELECT entity_id FROM post WHERE attribute MATCH 'body' AND value_indexed MATCH ?)
            AND post.attribute IN ('parentid', 'userid', 'body', 'replycount')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), term):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, term))

