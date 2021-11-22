from ./wavescript import nil
from strutils import nil
import tables, sets

proc parseAnsiwave*(ansiwave: string): tuple[cmds: Table[string, string], content: string] =
  var ctx = wavescript.initContext()
  ctx.stringCommands = ["/head.sig", "/head.time", "/head.key", "/head.algo", "/head.parent", "/head.last-sig", "/head.board"].toHashSet
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
  result.content = ansiwave[newline + 1 ..< ansiwave.len]
