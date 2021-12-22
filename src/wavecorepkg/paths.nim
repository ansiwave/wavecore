from os import `/`
from base64 import nil
from strutils import format
from urlly import `$`

when defined(emscripten):
  const
    address* = ""
    postAddress* = "http://post.ansiwave.net"
else:
  var
    address* = "http://bbs.ansiwave.net/bbs.html"
    postAddress* = "http://post.ansiwave.net"

var readUrl*: string

const
  staticFileDir* = "bbs"
  cloneDir* = "out"
  boardsDir* = "boards"
  ansiwavesDir* = "ansiwavez"
  dbDir* = "db"
  dbFilename* = "board.db"
  defaultBoard* = "kEKgeSd3-74Uy0bfOOJ9mj0qW3KpMpXBGrrQdUv190E"
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
  var url = urlly.parseUrl(address)
  url.paths = @[]
  let s = $url
  if strutils.endsWith(s, "/"):
    "$1$2".format(s, endpoint)
  else:
    "$1/$2".format(s, endpoint)

export base64.decode
