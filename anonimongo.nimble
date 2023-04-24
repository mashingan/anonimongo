# Package

version       = "0.7.0.rc"
author        = "Rahmatullah"
description   = "Anonimongo - Another pure Nim Mongo driver"
license       = "MIT"
srcDir        = "src"
#installDirs   = @["cinclude"]

# Dependencies

requires "nim >= 1.6.4", "nimSHA2 >= 0.1.1", "scram >= 0.1.9",
         "sha1 >= 1.1", "dnsclient >= 0.3.2", "supersnappy", "zippy"

from std/strutils import startsWith, endsWith
from std/strformat import fmt

task bson, "Unit test Bson":
  exec "testament p ./tests/test_bson_test.nim"
  rmFile "./tests/test_bson_test".toExe

const
  fileToTest = [
      "test_admmgmt_test",
      "test_bson_test",
      "test_change_streams",
      "test_client_test",
      "test_collections_test",
      "test_crud_test",
      "test_gridfs_test",
      "test_replication_sslcon",
    ]
  testsdir = "./tests"

task clean, "Clean up generated exe":
  for fname in fileToTest:
    rmFile fmt"./tests/{fname}".toExe
  for fname in [
    "utils_replica",
    "utils_test",
  ]:
    rmFile fmt"./tests/{fname}".toExe

task test, "Run testament":
  for filename in listFiles(testsdir):
    if "test_" in filename and
      filename.endsWith(".nim"):
      exec fmt"testament p {filename}"
    rmFile fmt"{filename}".toExe
  cleanTask()