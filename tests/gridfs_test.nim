import unittest
import ../src/anonimongo
import testutils

const filename {.strdefine.} = "d:/downloads/fmab28_opening3.mkv"

suite "GridFS implementation tests":
  var mongo: Mongo
  var grid: GridFS
  var db: Database
  var wr: WriteResult
  let dbname = "newtemptest"

  test "Mongo connected":
    mongo = newMongo()
    require waitfor mongo.connect
    db = mongo[dbname]

  test "Create default bucket":
    require db != nil
    grid = waitfor db.createBucket(chunkSize = 1.megabytes.int32)
    require grid != nil

  test "Upload file":
    wr = waitfor grid.uploadFile(filename)
    wr.success.reasonedCheck("Grid upload file", wr.reason)

  test "Download file":
    skip()

  test "Teardown bucket and db":
    skip()

  test "Shutdown mongo":
    skip()