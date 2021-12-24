# Package

version       = "0.1.1"
author        = "oakes"
description   = "Server and client utils for ANSIWAVE BBS"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim", "c", "h"]
bin           = @["wavecore"]

task dev, "Run dev version":
  exec "nimble run wavecore --testrun"

# Dependencies

requires "nim >= 1.2.6"
requires "urlly >= 1.0.0"
requires "puppy >= 1.4.0"
requires "flatty >= 0.2.3"
requires "zippy >= 0.7.3"
requires "paramidi >= 0.6.0"
