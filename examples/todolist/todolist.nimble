# Package

version       = "0.1.0"
author        = "Rahmatullah"
description   = "Prologue Todolist Example with Mongo"
license       = "MIT"
bin           = @["app"]
# srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.4.2", "prologue", "karax",
          "anonimongo"

task build, "Unit test Bson":
  exec "nim c -d:danger --threadAnalysis:off --passL:\"-static -no-pie\" app.nim"
