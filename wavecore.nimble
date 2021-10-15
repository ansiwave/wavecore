# Package

version       = "0.1.0"
author        = "oakes"
description   = "A new awesome nimble package"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim", "c"]
bin           = @["wavecore"]

task dev, "Run dev version":
  exec "nimble run wavecore"

# Dependencies

requires "nim >= 1.2.6"
requires "puppy >= 1.0.3"
requires "flatty >= 0.2.3"
requires "zippy >= 0.5.5"
