import wavecorepkg/db/sqlite3
from wavecorepkg/db/db_sqlite import sql
from wavecorepkg/db import nil
from sequtils import nil
from strutils import format
from os import nil

type
  User* = object
    id*: int64
    username*: string
    public_key*: string

proc initUser(entity: var User, stmt: PStmt, attr: string) =
  case attr:
  of "username":
    entity.username = $sqlite3.column_text(stmt, 2)
  of "public_key":
    entity.public_key = $sqlite3.column_text(stmt, 2)

proc selectUser*(conn: PSqlite3, username: string): User =
  const query =
    """
      SELECT * FROM user
      WHERE entity_id MATCH (SELECT entity_id FROM user WHERE attribute MATCH 'username' AND value_indexed MATCH ?)
            AND attribute IN ('username', 'public_key')
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
    parent_id*: int64
    user_id*: int64
    body*: string
    parent_ids*: string
    reply_count*: int64

proc initPost(entity: var Post, stmt: PStmt, attr: string) =
  case attr:
  of "parent_id":
    entity.parent_id = sqlite3.column_int(stmt, 2)
  of "user_id":
    entity.user_id = sqlite3.column_int(stmt, 2)
  of "body":
    entity.body = $sqlite3.column_text(stmt, 2)
  of "parent_ids":
    entity.parent_ids = $sqlite3.column_text(stmt, 2)
  of "reply_count":
    entity.reply_count = sqlite3.column_int(stmt, 2)

proc selectPost*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id MATCH ?
            AND attribute IN ('parent_id', 'user_id', 'body', 'reply_count')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  db.select[Post](conn, initPost, query, id)[0]

proc selectPostMetadata*(conn: PSqlite3, id: int64): Post =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id MATCH ?
            AND attribute IN ('parent_ids')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  db.select[Post](conn, initPost, query, id)[0]

proc selectPostChildren*(conn: PSqlite3, id: int64): seq[Post] =
  const query =
    """
      SELECT * FROM post
      WHERE entity_id IN (SELECT entity_id FROM post WHERE attribute MATCH 'parent_id' AND value_indexed MATCH ?)
            AND post.attribute IN ('parent_id', 'user_id', 'body', 'reply_count')
    """
  #for x in db_sqlite.fastRows(conn, sql("EXPLAIN QUERY PLAN" & query), id):
  #  echo x
  sequtils.toSeq(db.select[Post](conn, initPost, query, id))

proc insertPost*(conn: PSqlite3, entity: Post, extraFn: proc (x: var Post, id: int64) = nil): int64 =
  # TODO: strip ANSI codes out of entity.body since they don't need to be searchable
  db.insert(conn, "post", entity,
    proc (x: var Post, id: int64) =
      if extraFn != nil:
        extraFn(x, id)
      if x.parent_id > 0:
        # set the parent ids
        let parents = selectPostMetadata(conn, x.parent_id).parent_ids
        x.parent_ids =
          if parents.len == 0:
            $x.parent_id
          else:
            parents & ", " & $x.parent_id
        # update the parents' reply count
        let query =
          """
          UPDATE post
          SET value_indexed = value_indexed + 1
          WHERE attribute MATCH 'reply_count' AND
                CAST(entity_id AS INT) IN ($2)
          """.format(id, x.parent_ids)
        db_sqlite.exec(conn, sql query)
  )

