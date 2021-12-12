from os import `/`
from base64 import nil
from strutils import nil

when defined(emscripten):
  const
    address* = ""
    postAddress* = address
else:
  var
    address* = "http://test.ansiwave.net"
    postAddress* = address

const
  staticFileDir* = "bbs"
  boardsDir* = "boards"
  gitDir* = "git"
  ansiwavesDir* = "ansiwavez"
  dbDir* = "db"
  dbFilename* = "board.db"
  sysopPublicKey* = "Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE"

proc db*(board: string): string =
  boardsDir / board / gitDir / dbDir / dbFilename

proc ansiwavez*(board: string, filename: string): string =
  boardsDir / board / gitDir / ansiwavesDir / filename & ".ansiwavez"

proc encode*[T](data: T): string =
  result = base64.encode(data, safe = true)
  var i = result.len - 1
  while i >= 0 and result[i] == '=':
    strutils.delete(result, i..i)
    i -= 1

export base64.decode
