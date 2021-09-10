# Package

version       = "0.1.0"
author        = "oakes"
description   = "A new awesome nimble package"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["wavenet"]

task dev, "Run dev version":
  exec "nimble run wavenet"

# Dependencies

requires "nim >= 1.2.6"
requires "puppy >= 1.0.3"