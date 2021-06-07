# Package

version       = "0.1.0"
author        = "Rahmatullah"
description   = "Prologue Todolist Example with Mongo"
license       = "MIT"
bin           = @["app"]
# srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

# requires "nim >= 1.4.2", "prologue", "karax",
#          "nimSHA2 >= 0.1.1", "scram >= 0.1.9",
#          "sha1 >= 1.1", "dnsclient", "supersnappy", "zippy"
requires "nim >= 1.4.2", "prologue", "karax",
          "anonimongo"

task build, "Unit test Bson":
  exec "nim c -d:danger --threadAnalysis:off --passL:\"-static -no-pie\" app.nim"
