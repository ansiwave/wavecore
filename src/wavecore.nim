from ./wavecorepkg/testrun import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/db/vfs import nil
from ./wavecorepkg/paths import nil
from os import nil

const port = 3000

when isMainModule:
  if not os.dirExists(paths.staticFileDir):
    quit "Can't find directory: " & paths.staticFileDir
  vfs.register()
  var s = server.initServer("localhost", port, paths.staticFileDir)
  server.start(s)
  testrun.main(port)
  discard readLine(stdin)
  server.stop(s)
