# Package

version       = "0.9.0"
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
requires "puppy >= 2.1.0"
requires "flatty >= 0.3.4"
requires "paramidi >= 0.6.0"
requires "threading >= 0.1.0"
requires "ansiutils >= 0.2.0"
