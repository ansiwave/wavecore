from wavematrixpkg/server import nil

when isMainModule:
  var s = server.initServer("localhost", 3000)
  let thr = server.start(s)
  server.stop(s, thr)
