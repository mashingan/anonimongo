# Package

version       = "0.7.0"
author        = "Rahmatullah"
description   = "Anonimongo - Another pure Nim Mongo driver"
license       = "MIT"
srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.6.4", "nimSHA2 >= 0.1.1", "scram >= 0.1.9",
         "sha1 >= 1.1", "dnsclient >= 0.3.4", "supersnappy", "zippy",
         "https://github.com/mashingan/multisock >= 1.0.0"

task bson, "Unit test Bson":
  exec "nim c -r ./tests/test_bson_test.nim"
