# Package

version       = "0.2.0"
author        = "Rahmatullah"
description   = "Anonimongo - Another pure NIm MONGO driver"
license       = "MIT"
srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.0.2", "nimSHA2 >= 0.1.1", "scram >= 0.1.9",
         "sha1 >= 1.1"

task docs, "Build the doc":
  exec "nim doc2 -d:ssl --project --index:on --git.url:https://github.com/mashingan/anonimongo --git.commit:develop src/anonimongo.nim"
task index, "Build the index":
  exec "nim buildIndex -o:src/htmldocs/theindex.html src/htmldocs"