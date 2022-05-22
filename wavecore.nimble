# Package

version       = "0.7.0"
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
requires "puppy >= 1.5.3"
requires "flatty >= 0.2.4"
requires "paramidi >= 0.6.0"
requires "threading >= 0.1.0"
requires "ansiutils >= 0.1.0"
