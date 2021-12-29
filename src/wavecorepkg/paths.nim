from os import `/`
from base64 import nil
from strutils import format
from urlly import `$`

when defined(emscripten):
  const
    address* = ""
    postAddress* =
      when defined(release):
        "http://post.ansiwave.net"
      else:
        address
else:
  var
    address* =
      when defined(release):
        "http://bbs.ansiwave.net/bbs.html"
      else:
        "http://localhost:3000"
    postAddress* =
      when defined(release):
        "http://post.ansiwave.net"
      else:
        address

var readUrl*: string

const
  staticFileDir* = "bbs"
  cloneDir* = "out"
  boardsDir* = "boards"
  ansiwavesDir* = "ansiwavez"
  dbDir* = "db"
  dbFilename* = "board.db"
  miscDir* = "misc"
  purgatoryDir* = "purgatory"
  defaultBoard* =
    when defined(release):
      "kEKgeSd3-74Uy0bfOOJ9mj0qW3KpMpXBGrrQdUv190E"
    else:
      "Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE"

proc db*(board: string, isUrl: bool = false): string =
  if isUrl:
    boardsDir & "/" & board & "/" & dbDir & "/" & dbFilename
  else:
    boardsDir / board / dbDir / dbFilename

proc ansiwavez*(board: string, filename: string, isUrl: bool = false): string =
  if isUrl:
    boardsDir & "/" & board & "/" & ansiwavesDir & "/" & filename & ".ansiwavez"
  else:
    boardsDir / board / ansiwavesDir / filename & ".ansiwavez"

proc dbPurgatory*(board: string, isUrl: bool = false): string =
  if isUrl:
    boardsDir & "/" & board & "/" & miscDir & "/" & purgatoryDir & "/" & dbFilename
  else:
    boardsDir / board / miscDir / purgatoryDir / dbFilename

proc encode*[T](data: T): string =
  result = base64.encode(data, safe = true)
  var i = result.len - 1
  while i >= 0 and result[i] == '=':
    strutils.delete(result, i..i)
    i -= 1

proc initUrl*(address: string; endpoint: string): string =
  var url = urlly.parseUrl(address)
  url.paths = @[]
  let s = $url
  if strutils.endsWith(s, "/"):
    "$1$2".format(s, endpoint)
  else:
    "$1/$2".format(s, endpoint)

export base64.decode
