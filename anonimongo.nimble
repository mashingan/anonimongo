# Package

version       = "0.6.3"
author        = "Rahmatullah"
description   = "Anonimongo - Another pure Nim Mongo driver"
license       = "MIT"
srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.4.0", "nimSHA2 >= 0.1.1", "scram >= 0.1.9",
         "sha1 >= 1.1", "dnsclient >= 0.3.2", "supersnappy", "zippy"

task bson, "Unit test Bson":
  exec "testament p ./tests/test_bson_test.nim"
