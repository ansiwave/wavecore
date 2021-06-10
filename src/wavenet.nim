from wavenetpkg/server import nil

when isMainModule:
  var s = server.initServer("localhost", 3000)
  server.start(s)
  server.stop(s)
