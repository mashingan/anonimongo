# Package

version       = "0.1.0"
author        = "Rahmatullah"
description   = "Jester Upload with Mongo"
license       = "MIT"
bin           = @["app"]
# srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.4.0", "jester", "karax",
         "anonimongo#56a295f114e201d606f1309fdb1e77aaa8a44ba5", "ws", "httpbeast"

task build, "Default built command":
  exec "nim c -d:danger --gc:orc -d:useMalloc --passL:\"-static -no-pie\" app.nim"
