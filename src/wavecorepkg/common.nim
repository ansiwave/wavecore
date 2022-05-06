from ./wavescript import nil
from ./paths import nil
from ./ed25519 import nil
from strutils import nil
import tables, sets
from times import nil
import unicode
from ansiutils/codes import nil

proc parseTags*(tags: string): HashSet[string] =
  result = strutils.split(tags, ' ').toHashSet
  result.excl("")

type
  HeaderKind* = enum
    New, Edit, Tags, ExtraTags,

proc headers*(pubKey: string, target: string, kind: HeaderKind, board: string): string =
  strutils.join(
    [
      "/key " & pubKey,
      "/algo ed25519",
      "/target " & target,
      "/type " & (
          case kind:
          of New: "new"
          of Edit: "edit"
          of Tags: "tags"
          of ExtraTags: "extra-tags"
      ),
      "/board " & board,
    ],
    "\n",
  )

proc sign*(keyPair: ed25519.KeyPair, headers: string, content: string): tuple[body: string, sig: string] =
  result.body = "/time " & $times.toUnix(times.getTime()) & "\n"
  result.body &= headers & "\n\n" & content
  result.sig = paths.encode(ed25519.sign(keyPair, result.body))
  result.body = "/sig " & result.sig & "\n" & result.body

proc signWithHeaders*(keyPair: ed25519.KeyPair, content: string, target: string, kind: HeaderKind, board: string): tuple[body: string, sig: string] =
  sign(keyPair, headers(paths.encode(keyPair.public), target, kind, board), content)

proc splitAfterHeaders*(content: string): seq[string] =
  let idx = strutils.find(content, "\n\n")
  if idx == -1: # this should never happen
    @[""]
  else:
    strutils.splitLines(content[idx + 2 ..< content.len])

proc parseAnsiwave*(ansiwave: string): tuple[cmds: Table[string, string], headersAndContent: string, content: string] =
  let col = unicode.validateUtf8(ansiwave)
  if col != -1:
    raise newException(Exception, "Invalid UTF8 data")
  var ctx = wavescript.initContext()
  ctx.stringCommands = ["/sig", "/time", "/key", "/algo", "/target", "/type", "/board"].toHashSet
  let
    newline = strutils.find(ansiwave, "\n")
    doubleNewline = strutils.find(ansiwave, "\n\n")
  if newline == -1 or doubleNewline == -1 or newline == doubleNewline:
    raise newException(Exception, "Invalid ansiwave")
  let
    sigLine = ansiwave[0 ..< newline]
    headers = strutils.splitLines(ansiwave[newline + 1 ..< doubleNewline])
    content = ansiwave[doubleNewLine + 2 ..< ansiwave.len]
    sigCmd = wavescript.parse(ctx, sigLine)
  if sigCmd.kind != wavescript.Valid or sigCmd.name != "/sig":
    raise newException(Exception, "Invalid first header: " & sigLine)
  result.cmds[sigCmd.name] = sigCmd.args[0].name
  for header in headers:
    let cmd = wavescript.parse(ctx, header)
    if cmd.kind == wavescript.Valid:
      result.cmds[cmd.name] = cmd.args[0].name
  for cmd in ctx.stringCommands:
    if not result.cmds.hasKey(cmd):
      raise newException(Exception, "Required header not found: " & cmd)
  result.headersAndContent = ansiwave[newline + 1 ..< ansiwave.len]
  result.content = content

proc stripUnsearchableText*(content: string): string =
  let idx = strutils.find(content, "\n\n")
  if idx == -1: # this should never happen
    return ""
  else:
    let body = content[idx + 2 ..< content.len] # remove headers
    var newLines: seq[string]
    for line in strutils.splitLines(body):
      var
        chars = codes.stripCodes(line.toRunes) # remove escape codes
        newLine: seq[string]
      # replace ansi block chars with spaces
      for ch in chars:
        let s = $ch
        if s in wavescript.whitespaceChars:
          newLine.add(" ")
        else:
          newLine.add(s)
      # delete trailing spaces in each line
      for i in countdown(newLine.len-1, 0):
        if newLine[i] == " ":
          newLine.delete(i)
        else:
          break
      newLines.add(strutils.join(newLine))
    return strutils.join(newLines, "\n")

