from ./wavecorepkg/testrun import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/db/vfs import nil
from ./wavecorepkg/paths import nil

const port = 3000

when isMainModule:
  vfs.register()
  var s = server.initServer("localhost", port, paths.staticFileDir)
  server.start(s)
  testrun.main(s)
  discard readLine(stdin)
  server.stop(s)
