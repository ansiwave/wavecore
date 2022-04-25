from ./wavecorepkg/testrun import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/db/vfs import nil
from ./wavecorepkg/paths import nil
from os import `/`
from parseopt import nil
import tables
from zippy import nil

const port = 3000

when isMainModule:
  var
    p = parseopt.initOptParser()
    options: Table[string, string]
  while true:
    parseopt.next(p)
    case p.kind:
    of parseopt.cmdEnd:
      break
    of parseopt.cmdShortOption, parseopt.cmdLongOption:
      options[p.key] = p.val
    of parseopt.cmdArgument:
      continue

  if not os.dirExists(paths.staticFileDir):
    quit "Can't find directory: " & paths.staticFileDir

  if "upgrade" in options:
    proc upgradeBoard(board: string) =
      os.createDir(board / "ansiwave")
      for (kind, path) in os.walkDir(board / "ansiwavez"):
        let (dir, name, ext) = os.splitFile(path)
        if kind == os.pcFile and ext == ".ansiwavez":
          writeFile(board / "ansiwave" / name & ".ansiwave", zippy.uncompress(readFile(path), dataFormat = zippy.dfZlib))
          os.removeFile(path)
      os.removeDir(board / "ansiwavez")
    for (kind, board) in os.walkDir(paths.staticFileDir / "boards"):
      if kind == os.pcDir:
        if os.dirExists(board / "ansiwavez"):
          echo "Upgrading ", board
          os.moveDir(board, board / ".." / "temp")
          os.createDir(board)
          os.moveDir(board / ".." / "temp", board / "board")
          upgradeBoard(board / "board")
        if os.dirExists(board / "board" / "misc" / "limbo"):
          os.moveDir(board / "board" / "misc" / "limbo", board / "limbo")
          upgradeBoard(board / "limbo")
    quit 0

  vfs.register()
  var s = server.initServer("localhost", port, paths.staticFileDir, options)
  server.start(s)
  if "testrun" in options:
    testrun.main(port)
  when defined(release):
    while true:
      os.sleep(1000)
      if os.fileExists("stop"):
        server.stop(s)
  else:
    discard readLine(stdin)
    server.stop(s)
