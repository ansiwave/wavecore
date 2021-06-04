import db_sqlite

proc initTables*(conn: DbConn) =
  conn.exec sql"""
  CREATE TABLE entity (
    id           INTEGER NOT NULL PRIMARY KEY,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  conn.exec sql"""
  CREATE TABLE entity_attr (
    id           INTEGER NOT NULL PRIMARY KEY,
    attr         TEXT NOT NULL,
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  conn.exec sql"""
  CREATE TABLE entity_value (
    id                 INTEGER NOT NULL PRIMARY KEY,
    value              TEXT NOT NULL,
    created_ts         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    entity_id          INTEGER NOT NULL,
    entity_attr_id     INTEGER NOT NULL,
    FOREIGN KEY(entity_id) REFERENCES entity(id),
    FOREIGN KEY(entity_attr_id) REFERENCES entity_attr(id)
  )"""
