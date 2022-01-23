# Package

version       = "0.4.0"
author        = "oakes"
description   = "Server and client utils for ANSIWAVE BBS"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim", "c", "h"]
bin           = @["wavecore"]

task dev, "Run dev version":
  exec "nimble run wavecore --testrun --disable-limbo"

# Dependencies

requires "nim >= 1.2.6"
requires "urlly >= 1.0.0"
requires "puppy >= 1.5.1"
requires "flatty >= 0.2.3"
requires "zippy >= 0.7.3"
requires "paramidi >= 0.6.0"
