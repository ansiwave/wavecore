{.passC: "-DSQLITE_ENABLE_FTS5".}

import sqlite3
from db_sqlite import sql, SqlQuery
from puppy import nil
from strutils import nil
from sequtils import nil
from parseutils import nil

type
  sqlite3_vfs* {.bycopy.} = object
    iVersion*: cint            ##  Structure version number (currently 3)
    szOsFile*: cint            ##  Size of subclassed sqlite3_file
    mxPathname*: cint          ##  Maximum file pathname length
    pNext*: ptr sqlite3_vfs     ##  Next registered VFS
    zName*: cstring            ##  Name of this virtual file system
    pAppData*: pointer         ##  Pointer to application-specific data
    xOpen*: proc (a1: ptr sqlite3_vfs; zName: cstring; a3: ptr sqlite3_file; flags: cint;
                pOutFlags: ptr cint): cint {.cdecl.}
    xDelete*: proc (a1: ptr sqlite3_vfs; zName: cstring; syncDir: cint): cint {.cdecl.}
    xAccess*: proc (a1: ptr sqlite3_vfs; zName: cstring; flags: cint; pResOut: ptr cint): cint {.cdecl.}
    xFullPathname*: proc (a1: ptr sqlite3_vfs; zName: cstring; nOut: cint; zOut: cstring): cint {.cdecl.}
    xDlOpen*: proc (a1: ptr sqlite3_vfs; zFilename: cstring): pointer {.cdecl.}
    xDlError*: proc (a1: ptr sqlite3_vfs; nByte: cint; zErrMsg: cstring) {.cdecl.}
    xDlSym*: proc (): proc (a1: ptr sqlite3_vfs; a2: pointer; zSymbol: cstring): pointer {.cdecl.}
    xDlClose*: proc (a1: ptr sqlite3_vfs; a2: pointer) {.cdecl.}
    xRandomness*: proc (a1: ptr sqlite3_vfs; nByte: cint; zOut: cstring): cint {.cdecl.}
    xSleep*: proc (a1: ptr sqlite3_vfs; microseconds: cint): cint {.cdecl.}
    xCurrentTime*: proc (a1: ptr sqlite3_vfs; a2: ptr cdouble): cint {.cdecl.}
    xGetLastError*: proc (a1: ptr sqlite3_vfs; a2: cint; a3: cstring): cint {.cdecl.}
    ## * The methods above are in version 1 of the sqlite_vfs object
    ## * definition.  Those that follow are added in version 2 or later
    ##
    xCurrentTimeInt64*: proc (a1: ptr sqlite3_vfs; a2: ptr int64): cint {.cdecl.}
    ## * The methods above are in versions 1 and 2 of the sqlite_vfs object.
    ## * Those below are for version 3 and greater.
    ##
    xSetSystemCall*: proc (a1: ptr sqlite3_vfs; zName: cstring; a3: pointer): cint {.cdecl.}
    xGetSystemCall*: proc (a1: ptr sqlite3_vfs; zName: cstring): pointer {.cdecl.}
    xNextSystemCall*: proc (a1: ptr sqlite3_vfs; zName: cstring): cstring {.cdecl.}
    ## * The methods above are in versions 1 through 3 of the sqlite_vfs object.
    ## * New fields may be appended in future versions.  The iVersion
    ## * value will increment whenever this happens.
    ##
  sqlite3_io_methods* {.bycopy.} = object
    iVersion*: cint
    xClose*: proc (a1: ptr sqlite3_file): cint {.cdecl.}
    xRead*: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.}
    xWrite*: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.}
    xTruncate*: proc (a1: ptr sqlite3_file; size: int64): cint {.cdecl.}
    xSync*: proc (a1: ptr sqlite3_file; flags: cint): cint {.cdecl.}
    xFileSize*: proc (a1: ptr sqlite3_file; pSize: ptr int64): cint {.cdecl.}
    xLock*: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.}
    xUnlock*: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.}
    xCheckReservedLock*: proc (a1: ptr sqlite3_file; pResOut: ptr cint): cint {.cdecl.}
    xFileControl*: proc (a1: ptr sqlite3_file; op: cint; pArg: pointer): cint {.cdecl.}
    xSectorSize*: proc (a1: ptr sqlite3_file): cint {.cdecl.}
    xDeviceCharacteristics*: proc (a1: ptr sqlite3_file): cint {.cdecl.}
    ##  Methods above are valid for version 1
    xShmMap*: proc (a1: ptr sqlite3_file; iPg: cint; pgsz: cint; a4: cint; a5: ptr pointer): cint {.cdecl.}
    xShmLock*: proc (a1: ptr sqlite3_file; offset: cint; n: cint; flags: cint): cint {.cdecl.}
    xShmBarrier*: proc (a1: ptr sqlite3_file) {.cdecl.}
    xShmUnmap*: proc (a1: ptr sqlite3_file; deleteFlag: cint): cint {.cdecl.}
    ##  Methods above are valid for version 2
    xFetch*: proc (a1: ptr sqlite3_file; iOfst: int64; iAmt: cint; pp: ptr pointer): cint {.cdecl.}
    xUnfetch*: proc (a1: ptr sqlite3_file; iOfst: int64; p: pointer): cint {.cdecl.}
    ##  Methods above are valid for version 3
    ##  Additional methods may be added in future releases
  sqlite3_file* {.bycopy.} = object
    pMethods*: ptr sqlite3_io_methods ##  Methods for an open file

var readUrl*: string

let customMethods = sqlite3_io_methods(
  iVersion: 3,
  xClose: proc (a1: ptr sqlite3_file): cint {.cdecl.} = SQLITE_OK,
  xRead: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.} =
    let res = puppy.fetch(puppy.Request(
      url: puppy.parseUrl(readUrl),
      verb: "get",
      headers: @[puppy.Header(key: "Range", value: "bytes=" & $iOfst & "-" & $(iOfst+iAmt-1))]
    ))
    if res.code == 206:
      assert res.body.len == iAmt
      copyMem(a2, res.body[0].addr, res.body.len)
      SQLITE_OK
    else:
      SQLITE_ERROR
  ,
  xWrite: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.} = SQLITE_OK,
  xTruncate: proc (a1: ptr sqlite3_file; size: int64): cint {.cdecl.} = SQLITE_OK,
  xSync: proc (a1: ptr sqlite3_file; flags: cint): cint {.cdecl.} = SQLITE_OK,
  xFileSize: proc (a1: ptr sqlite3_file; pSize: ptr int64): cint {.cdecl.} =
    let res = puppy.fetch(puppy.Request(
      url: puppy.parseUrl(readUrl),
      verb: "get",
      headers: @[puppy.Header(key: "Range", value: "bytes=0-0")]
    ))
    if res.code == 206:
      for header in res.headers:
        if header.key == "Content-Range":
          let vals = sequtils.toSeq(strutils.split(header.value, {' ', '/'}))
          if vals.len == 3 and vals[0] == "bytes":
            var size = 0
            if parseutils.parseInt(vals[2], size) > 0:
              pSize[] = size
              return SQLITE_OK
    SQLITE_ERROR
  ,
  xLock: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.} = SQLITE_OK,
  xUnlock: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.} = SQLITE_OK,
  xCheckReservedLock: proc (a1: ptr sqlite3_file; pResOut: ptr cint): cint {.cdecl.} = SQLITE_OK,
  xFileControl: proc (a1: ptr sqlite3_file; op: cint; pArg: pointer): cint {.cdecl.} = SQLITE_OK,
  xSectorSize: proc (a1: ptr sqlite3_file): cint {.cdecl.} = 0,
  xDeviceCharacteristics: proc (a1: ptr sqlite3_file): cint {.cdecl.} = SQLITE_OK,
  xShmMap: nil,
  xShmLock: nil,
  xShmBarrier: nil,
  xShmUnmap: nil,
  xFetch: nil,
  xUnfetch: nil,
)

proc sqlite3_open_v2(filename: cstring, ppDb: var PSqlite3, flags: cint, zVfs: cstring): cint {.cdecl, importc.}
proc sqlite3_vfs_register(vfs: ptr sqlite3_vfs, makeDflt: cint): cint {.cdecl, importc.}

let vfs = sqlite3_vfs(
  iVersion: 3,            ##  Structure version number (currently 3)
  szOsFile: cint(sizeof(sqlite3_file)),            ##  Size of subclassed sqlite3_file
  mxPathname: 100,          ##  Maximum file pathname length
  pNext: nil,     ##  Next registered VFS
  zName: "http",            ##  Name of this virtual file system
  pAppData: nil,         ##  Pointer to application-specific data
  xOpen: proc (a1: ptr sqlite3_vfs; zName: cstring; a3: ptr sqlite3_file; flags: cint;
              pOutFlags: ptr cint): cint {.cdecl.} =
    a3.pMethods = customMethods.unsafeAddr
    SQLITE_OK
  ,
  xDelete: proc (a1: ptr sqlite3_vfs; zName: cstring; syncDir: cint): cint {.cdecl.} =
    SQLITE_OK
  ,
  xAccess: proc (a1: ptr sqlite3_vfs; zName: cstring; flags: cint; pResOut: ptr cint): cint {.cdecl.} =
    SQLITE_OK
  ,
  xFullPathname: proc (a1: ptr sqlite3_vfs; zName: cstring; nOut: cint; zOut: cstring): cint {.cdecl.} =
    SQLITE_OK
  ,
  xDlOpen: nil,
  xDlError: nil,
  xDlSym: nil,
  xDlClose: nil,
  xRandomness: nil,
  xSleep: nil,
  xCurrentTime: nil,
  xGetLastError: nil,
  xCurrentTimeInt64: nil,
  xSetSystemCall: nil,
  xGetSystemCall: nil,
  xNextSystemCall: nil,
)
assert SQLITE_OK == sqlite3_vfs_register(vfs.unsafeAddr, 0)

const
  SQLITE_OPEN_READONLY = 1
  SQLITE_OPEN_READWRITE = 2
  SQLITE_OPEN_CREATE = 4

import bitops

proc open*(filename: string, http: bool = false): db_sqlite.DbConn =
  var db: db_sqlite.DbConn
  if sqlite3_open_v2(filename, db, if http: SQLITE_OPEN_READONLY else: bitor(SQLITE_OPEN_READWRITE, SQLITE_OPEN_CREATE), if http: "http".cstring else: nil) == SQLITE_OK:
    result = db
  else:
    db_sqlite.dbError(db)

proc init*(conn: PSqlite3) =
  db_sqlite.exec conn, sql"""
  CREATE TABLE entity (
    created_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )"""

  # the value_indexed column contains only human-readable text that must be searchable
  # the value_unindexed column contains data that should be excluded from the fts index
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE user USING fts5 (entity_id, attribute, value_indexed, value_unindexed UNINDEXED)"
  db_sqlite.exec conn, sql"CREATE VIRTUAL TABLE post USING fts5 (entity_id, attribute, value_indexed, value_unindexed UNINDEXED)"

proc dbFormat(formatstr: SqlQuery, args: varargs[string]): string =
  result = ""
  var a = 0
  for c in items(string(formatstr)):
    if c == '?':
      add(result, db_sqlite.dbQuote(args[a]))
      inc(a)
    else:
      add(result, c)

proc setupQuery(db: PSqlite3, query: SqlQuery,
                args: varargs[string]): PStmt =
  assert(not db.isNil, "Database not connected.")
  var q = dbFormat(query, args)
  if prepare_v2(db, q, q.len.cint, result, nil) != SQLITE_OK: db_sqlite.dbError(db)

iterator select*[T](db: PSqlite3, ctor: proc (x: var T, stmt: PStmt, col: int32), query: SqlQuery, args: varargs[string, `$`]): T =
  var stmt = setupQuery(db, query, args)
  var obj: T
  try:
    while step(stmt) == SQLITE_ROW:
      var cols = column_count(stmt)
      for col in 0 .. cols-1:
        ctor(obj, stmt, col)
      yield obj
  finally:
    if finalize(stmt) != SQLITE_OK: db_sqlite.dbError(db)

proc insert*[T](conn: PSqlite3, table: string, values: T): int64 =
  db_sqlite.exec(conn, sql"BEGIN TRANSACTION")
  db_sqlite.exec(conn, sql"INSERT INTO entity DEFAULT VALUES")
  result = sqlite3.last_insert_rowid(conn)
  for k, v in values.fieldPairs:
    when k != "id":
      db_sqlite.exec(conn, sql("INSERT INTO " & table & " (entity_id, attribute, value_indexed) VALUES (?, ?, ?)"), result, k, v)
  db_sqlite.exec(conn, sql"COMMIT")
