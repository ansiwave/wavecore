from os import `/`
from base64 import nil
from strutils import format
from urlly import `$`

const
  defaultGetAddress* {.strdefine.} = "undefined"
  defaultPostAddress* {.strdefine.} = "undefined"
  defaultBoard* {.strdefine.} = "undefined"

when defaultGetAddress == "undefined":
  {.error: "You must define defaultGetAddress".}
elif defaultPostAddress == "undefined":
  {.error: "You must define defaultPostAddress".}
elif defaultBoard == "undefined":
  {.error: "You must define defaultBoard".}

var
  address* = defaultGetAddress
  postAddress* = defaultPostAddress

var readUrl*: string

const
  staticFileDir* = "bbs"
  boardsDir* = "boards"
  boardDir* = "board"
  limboDir* = "limbo"
  ansiwaveDir* = "ansiwave"
  dbDir* = "db"
  dbFilename* = "board.db"

proc db*(board: string, isUrl: bool = false, limbo: bool = false): string =
  if isUrl:
    if limbo:
      boardsDir & "/" & board & "/" & limboDir & "/" & dbDir & "/" & dbFilename
    else:
      boardsDir & "/" & board & "/" & boardDir & "/" & dbDir & "/" & dbFilename
  else:
    if limbo:
      boardsDir / board / limboDir / dbDir / dbFilename
    else:
      boardsDir / board / boardDir / dbDir / dbFilename

proc ansiwave*(board: string, filename: string, isUrl: bool = false, limbo: bool = false): string =
  if isUrl:
    if limbo:
      boardsDir & "/" & board & "/" & limboDir & "/" & ansiwaveDir & "/" & filename & ".ansiwave"
    else:
      boardsDir & "/" & board & "/" & boardDir & "/" & ansiwaveDir & "/" & filename & ".ansiwave"
  else:
    if limbo:
      boardsDir / board / limboDir / ansiwaveDir / filename & ".ansiwave"
    else:
      boardsDir / board / boardDir / ansiwaveDir / filename & ".ansiwave"

proc encode*[T](data: T): string =
  result = base64.encode(data, safe = true)
  var i = result.len - 1
  while i >= 0 and result[i] == '=':
    strutils.delete(result, i..i)
    i -= 1

proc initUrl*(address: string; endpoint: string): string =
  if address == "" or strutils.endsWith(address, "/"):
    "$1$2".format(address, endpoint)
  else:
    # the address doesn't end in a slash, so assume the part at the end of the path
    # is a file and remove it.
    var url = urlly.parseUrl(address)
    if url.paths.len > 0:
      discard url.paths.pop()
    let s = $url
    if strutils.endsWith(s, "/"):
      "$1$2".format(s, endpoint)
    else:
      "$1/$2".format(s, endpoint)

export base64.decode
