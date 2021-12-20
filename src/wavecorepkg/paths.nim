from os import `/`
from base64 import nil
from strutils import format

when defined(emscripten):
  const
    address* = ""
    postAddress* = "http://post.ansiwave.net"
else:
  var
    address* = "http://bbs.ansiwave.net"
    postAddress* = "http://post.ansiwave.net"

var readUrl*: string

const
  staticFileDir* = "bbs"
  cloneDir* = "out"
  boardsDir* = "boards"
  ansiwavesDir* = "ansiwavez"
  dbDir* = "db"
  dbFilename* = "board.db"
  defaultBoard* = "Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE"
  miscDir* = "misc"

proc db*(board: string): string =
  boardsDir / board / dbDir / dbFilename

proc ansiwavez*(board: string, filename: string): string =
  boardsDir / board / ansiwavesDir / filename & ".ansiwavez"

proc encode*[T](data: T): string =
  result = base64.encode(data, safe = true)
  var i = result.len - 1
  while i >= 0 and result[i] == '=':
    strutils.delete(result, i..i)
    i -= 1

proc initUrl*(address: string; endpoint: string): string =
  if strutils.endsWith(address, "/"):
    "$1$2".format(address, endpoint)
  else:
    "$1/$2".format(address, endpoint)

export base64.decode
