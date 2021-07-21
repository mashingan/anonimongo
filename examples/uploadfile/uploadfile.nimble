# Package

version       = "0.1.0"
author        = "Rahmatullah"
description   = "Jester Upload with Mongo"
license       = "MIT"
bin           = @["app"]
# srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.4.2", "jester", "karax",
         "anonimongo#head", "ws", "httpbeast"

task build, "Unit test Bson":
  exec "nim c -d:danger --passL:\"-static -no-pie\" app.nim"
