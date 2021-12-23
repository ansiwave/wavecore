import ./sqlite3
from os import `/`
from strformat import fmt
from strutils import nil
from ../paths import nil

import ../client
from urlly import nil
import bitops
import json

const chunkSize = bitand(262144 + 0xffff, bitnot 0xffff)

when defined(multiplexSqlite):
  {.passC: "-DSQLITE_MULTIPLEX_CHUNK_SIZE=" & $chunkSize.}
  {.compile: "sqlite3_multiplex.c".}

  proc sqlite3_multiplex_initialize(zOrigVfsName: cstring, makeDefault: cint): cint {.cdecl, importc.}

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

const SQLITE_IOCAP_IMMUTABLE = 0x00002000

let customMethods = sqlite3_io_methods(
  iVersion: 3,
  xClose: proc (a1: ptr sqlite3_file): cint {.cdecl.} = SQLITE_OK,
  xRead: proc (a1: ptr sqlite3_file; pBuf: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.} =
    var
      buf = pBuf
      amt = iAmt
      off = iOfst
    while amt > 0:
      let i = int(off.int / chunkSize.int)
      var extra = cint(((off mod chunkSize).int + amt) - chunkSize)
      if extra < 0: extra = 0
      amt -= extra;
      let
        suffix = if i == 0: "" else : "{i:010}".fmt
        firstByte = off mod chunkSize
        lastByte = firstByte + amt - 1
      var res = fetch(Request(
        url: urlly.parseUrl(paths.readUrl & suffix),
        verb: "get",
        headers: @[
          Header(key: "Range", value: "bytes=" & $firstByte & "-" & $lastByte),
          Header(key: "Cache-Control", value: "no-cache, no-store"),
        ]
      ))
      if res.code == 206:
        assert res.body.len == amt
        copyMem(buf, res.body[0].addr, res.body.len)
      else:
        return SQLITE_ERROR
      buf = cast[pointer](cast[int](buf) + amt)
      off += amt
      amt = extra
    SQLITE_OK
  ,
  xWrite: proc (a1: ptr sqlite3_file; a2: pointer; iAmt: cint; iOfst: int64): cint {.cdecl.} = SQLITE_OK,
  xTruncate: proc (a1: ptr sqlite3_file; size: int64): cint {.cdecl.} = SQLITE_OK,
  xSync: proc (a1: ptr sqlite3_file; flags: cint): cint {.cdecl.} = SQLITE_OK,
  xFileSize: proc (a1: ptr sqlite3_file; pSize: ptr int64): cint {.cdecl.} =
    let res = fetch(Request(
      url: urlly.parseUrl(paths.readUrl & ".json"),
      verb: "get",
      headers: @[
        Header(key: "Cache-Control", value: "no-cache, no-store"),
      ]
    ))
    if res.code == 200:
      try:
        let data = parseJson(res.body)
        pSize[] = data["total-size"].num
        return SQLITE_OK
      except Exception as ex:
        return SQLITE_ERROR
  ,
  xLock: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.} = SQLITE_OK,
  xUnlock: proc (a1: ptr sqlite3_file; a2: cint): cint {.cdecl.} = SQLITE_OK,
  xCheckReservedLock: proc (a1: ptr sqlite3_file; pResOut: ptr cint): cint {.cdecl.} = SQLITE_OK,
  xFileControl: proc (a1: ptr sqlite3_file; op: cint; pArg: pointer): cint {.cdecl.} = SQLITE_OK,
  xSectorSize: proc (a1: ptr sqlite3_file): cint {.cdecl.} = 0,
  xDeviceCharacteristics: proc (a1: ptr sqlite3_file): cint {.cdecl.} = SQLITE_IOCAP_IMMUTABLE,
  xShmMap: nil,
  xShmLock: nil,
  xShmBarrier: nil,
  xShmUnmap: nil,
  xFetch: nil,
  xUnfetch: nil,
)

let httpVfs = sqlite3_vfs(
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

proc sqlite3_vfs_register(vfs: ptr sqlite3_vfs, makeDflt: cint): cint {.cdecl, importc.}

proc register*() =
  when defined(multiplexSqlite):
    doAssert SQLITE_OK == sqlite3_multiplex_initialize(nil, 0)
  doAssert SQLITE_OK == sqlite3_vfs_register(httpVfs.unsafeAddr, 0)

when defined(multiplexSqlite):
  proc wavecore_save_manifest(fileName: cstring, fileSize: int64): cint {.cdecl, exportc.} =
    let name = $fileName
    if strutils.endsWith(name, "/" & paths.dbFilename): # make sure this is the main db file, not the journal file
      writeFile(name & ".json", $ %* {"total-size": fileSize, "chunk-size": chunkSize})
    0

