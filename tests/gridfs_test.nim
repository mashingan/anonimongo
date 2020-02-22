import unittest, os, osproc
import ../src/anonimongo
import testutils

const filename {.strdefine.} = "d:/downloads/fmab28_opening3.mkv"

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "GridFS implementation tests":
  test "Mongo server is running":
    if runlocal:
      require mongorun.running
    else:
      skip()

  var mongo: Mongo
  var grid: GridFS
  var db: Database
  var wr: WriteResult
  let dbname = "newtemptest"
  let (_, fname, ext) = splitFile filename
  let dwfile = fname & ext

  test "Connect to localhost and authentication":
    mongo = testsetup()
    require(mongo != nil)
    require(mongo.authenticated)
    db = mongo[dbname]

  test "Create default bucket":
    require db != nil
    grid = waitfor db.createBucket(chunkSize = 1.megabytes.int32)
    require grid != nil

  test "Upload file":
    wr = waitfor grid.uploadFile(filename)
    wr.success.reasonedCheck("Grid upload file", wr.reason)

  test "Download file":
    removeFile dwfile
    wr = waitfor grid.downloadFile("fmab_opening3.mkv")
    check not wr.success # because no such file uploaded
    wr = waitfor grid.downloadFile(dwfile)
    wr.success.reasonedCheck("Grid download file", wr.reason)
    check fileExists(dwfile)

  test "Teardown bucket and db":
    require db != nil
    wr = waitFor db.dropDatabase
    wr.success.reasonedCheck("dropDatabase error", wr.reason)

  test "Shutdown mongo":
    if runlocal:
      require mongo != nil
      wr = waitFor mongo.shutdown(timeout = 10)
      check wr.success
    else:
      skip()

  close mongo
  if runlocal:
    if mongorun != nil and mongorun.running: kill mongorun
    close mongorun