{.passC: "-DSQLITE_ENABLE_FTS5".}

import sqlite3
from db_sqlite import sql, SqlQuery
from puppy import nil

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

var origMethods: ptr sqlite3_io_methods
var readUrl: string

template withHttp*(url: string, body: untyped): untyped =
  readUrl = url
  try:
    body
  finally:
    readUrl = ""

let customMethods = sqlite3_io_methods(
  iVersion: 3,
  xClose: proc (a1: ptr sqlite3_file): cint {.cdecl.} = origMethods.xClose(a1),
  xRead: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.} =
    if readUrl == "":
      origMethods.xRead(a1, a2, iAmt, iOfst)
    else:
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
  xWrite: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.} = origMethods.xWrite(a1, a2, iAmt, iOfst),
  xTruncate: proc (a1: ptr sqlite3_file; size: int64): cint {.cdecl.} = origMethods.xTruncate(a1, size),
  xSync: proc (a1: ptr sqlite3_file; flags: cint): cint {.cdecl.} = origMethods.xSync(a1, flags),
  xFileSize: proc (a1: ptr sqlite3_file; pSize: ptr int64): cint {.cdecl.} = origMethods.xFileSize(a1, pSize),
  xLock: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.} = origMethods.xLock(a1, a2),
  xUnlock: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.} = origMethods.xUnlock(a1, a2),
  xCheckReservedLock: proc (a1: ptr sqlite3_file; pResOut: ptr cint): cint {.cdecl.} = origMethods.xCheckReservedLock(a1, pResOut),
  xFileControl: proc (a1: ptr sqlite3_file; op: cint; pArg: pointer): cint {.cdecl.} = origMethods.xFileControl(a1, op, pArg),
  xSectorSize: proc (a1: ptr sqlite3_file): cint {.cdecl.} = origMethods.xSectorSize(a1),
  xDeviceCharacteristics: proc (a1: ptr sqlite3_file): cint {.cdecl.} = origMethods.xDeviceCharacteristics(a1),
  xShmMap: proc (a1: ptr sqlite3_file; iPg: cint; pgsz: cint; a4: cint; a5: ptr pointer): cint {.cdecl.} = origMethods.xShmMap(a1, iPg, pgsz, a4, a5),
  xShmLock: proc (a1: ptr sqlite3_file; offset: cint; n: cint; flags: cint): cint {.cdecl.} = origMethods.xShmLock(a1, offset, n, flags),
  xShmBarrier: proc (a1: ptr sqlite3_file) {.cdecl.} = origMethods.xShmBarrier(a1),
  xShmUnmap: proc (a1: ptr sqlite3_file; deleteFlag: cint): cint {.cdecl.} = origMethods.xShmUnmap(a1, deleteFlag),
  xFetch: proc (a1: ptr sqlite3_file; iOfst: int64; iAmt: cint; pp: ptr pointer): cint {.cdecl.} = origMethods.xFetch(a1, iOfst, iAmt, pp),
  xUnfetch: proc (a1: ptr sqlite3_file; iOfst: int64; p: pointer): cint {.cdecl.} = origMethods.xUnfetch(a1, iOfst, p),
)

proc sqlite3_vfs_find(vfsName: cstring): ptr sqlite3_vfs {.cdecl, importc.}

var origOpen: proc (a1: ptr sqlite3_vfs; zName: cstring; a3: ptr sqlite3_file; flags: cint; pOutFlags: ptr cint): cint {.cdecl.}

proc customOpen(a1: ptr sqlite3_vfs; zName: cstring; a3: ptr sqlite3_file; flags: cint; pOutFlags: ptr cint): cint {.cdecl.} =
  result = origOpen(a1, zName, a3, flags, pOutFlags)
  origMethods = a3.pMethods
  a3.pMethods = customMethods.unsafeAddr

var vfs = sqlite3_vfs_find(nil)
assert vfs != nil
origOpen = vfs.xOpen
vfs.xOpen = customOpen

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
