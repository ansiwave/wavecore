from os import `/`
from ./db/entities import nil
from ./ed25519 import nil
from base64 import nil

const
  port* = 3000
  address* = "http://localhost:" & $port
  dbFilename* = "board.db"
  ansiwavesDir* = "ansiwavez"

when defined(emscripten):
  const sysopPublicKey* = base64.encode(staticRead(".." / ".." / "pubkey"), safe = true)
else:
  let
    sysopKeys* = block:
      let path = ".." / "wavecore" / "privkey"
      if os.fileExists(path):
        echo "Using existing sysop key"
        let privKeyStr = readFile(path)
        var privKey: ed25519.PrivateKey
        copyMem(privKey.addr, privKeyStr[0].unsafeAddr, privKeyStr.len)
        ed25519.initKeyPair(privkey)
      else:
        echo "Creating new sysop key"
        let keys = ed25519.initKeyPair()
        writeFile(path, keys.private)
        writeFile(".." / "wavecore" / "pubkey", keys.public)
        keys
    sysopPublicKey* = entities.initPublicKey(sysopKeys.public)

let
  staticFileDir* = "bbs"
  boardDir* = staticFileDir / sysopPublicKey
