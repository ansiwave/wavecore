from ./wavescript import nil
from ./paths import nil
from ./ed25519 import nil
from strutils import nil
import tables, sets
from times import nil

proc headers*(pubKey: string, target: string, isNew: bool): string =
  strutils.join(
    [
      "/head.key " & pubKey,
      "/head.algo ed25519",
      "/head.target " & target,
      "/head.type " & (if isNew: "new" else: "edit"),
      "/head.board " & paths.sysopPublicKey,
    ],
    "\n",
  )

proc sign*(keyPair: ed25519.KeyPair, headers: string, content: string): tuple[body: string, sig: string] =
  result.body = "/head.time " & $times.toUnix(times.getTime()) & "\n"
  result.body &= headers & "\n\n" & content
  result.sig = paths.encode(ed25519.sign(keyPair, result.body))
  result.body = "/head.sig " & result.sig & "\n" & result.body

proc signWithHeaders*(keyPair: ed25519.KeyPair, content: string, target: string, isNew: bool): tuple[body: string, sig: string] =
  sign(keyPair, headers(paths.encode(keyPair.public), target, isNew), content)

proc parseAnsiwave*(ansiwave: string): tuple[cmds: Table[string, string], headersAndContent: string, content: string] =
  var ctx = wavescript.initContext()
  ctx.stringCommands = ["/head.sig", "/head.time", "/head.key", "/head.algo", "/head.target", "/head.type", "/head.board"].toHashSet
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
  if sigCmd.kind != wavescript.Valid or sigCmd.name != "/head.sig":
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
