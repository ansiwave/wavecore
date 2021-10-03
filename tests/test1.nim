import unittest
from wavecorepkg/client import nil
from wavecorepkg/server import nil
import json

const
  port = 3000
  config = client.Config(
    address: "http://localhost:" & $port,
  )

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  server.start(s)
  try:
    var c = client.initClient(config)
    discard client.post(c, "test", %* {"success": true})
    expect client.ClientException:
      discard client.post(c, "test", nil)
  finally:
    server.stop(s)

