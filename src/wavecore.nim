from ./wavecorepkg/testrun import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/db import nil
from ./wavecorepkg/db/vfs import nil
from ./wavecorepkg/paths import nil
from os import nil
from parseopt import nil
import tables

const port = 3000

when isMainModule:
  var
    p = parseopt.initOptParser()
    options: Table[string, string]
    dbPath = ""
  while true:
    parseopt.next(p)
    case p.kind:
    of parseopt.cmdEnd:
      break
    of parseopt.cmdShortOption, parseopt.cmdLongOption:
      options[p.key] = p.val
    of parseopt.cmdArgument:
      if dbPath == "":
        dbPath = p.key
      else:
        quit "Invalid args"
  if dbPath != "":
    vfs.register()
    db.shell(dbPath)
  else:
    if not os.dirExists(paths.staticFileDir):
      quit "Can't find directory: " & paths.staticFileDir
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
