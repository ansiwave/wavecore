from os import `/`
from ./ed25519 import nil
from base64 import nil
from strutils import nil

const
  port* = 3000
  address* = "http://localhost:" & $port
  boardsDir* = "boards"
  ansiwavesDir* = "ansiwavez"
  dbDir* = "db"
  dbFilename* = "board.db"

proc db*(board: string): string =
  boardsDir / board / dbDir / dbFilename

proc ansiwavez*(board: string, filename: string): string =
  boardsDir / board / ansiwavesDir / filename & ".ansiwavez"

proc encode*[T](data: T): string =
  result = base64.encode(data, safe = true)
  var i = result.len - 1
  while i >= 0 and result[i] == '=':
    strutils.delete(result, i..i)
    i -= 1

export base64.decode

when defined(emscripten):
  const sysopPublicKey* = encode(staticRead(".." / ".." / "pubkey"))
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
    sysopPublicKey* = encode(sysopKeys.public)
