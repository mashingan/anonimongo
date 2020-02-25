import unittest, os, osproc, strformat, sequtils, asyncfile
import sugar
import ../src/anonimongo
import testutils

{.warning[UnusedImport]: off.}

const filename {.strdefine.} = "d:/downloads/fmab28_opening3.mkv"

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

proc insert5files(g: GridFS, fname: string): bool =
  var f: AsyncFile
  try:
    f = openAsync(fname)
  except:
    echo getCurrentExceptionMsg()
    return
  defer: close f
  let (_, thename, ext) = splitFile fname
  var wrs = newseq[Future[WriteResult]](5)
  for i in 0 .. wrs.high:
    let newname = &"{thename}_{i}{ext}"
    wrs[i] = g.uploadFile(f, newname)
  (waitfor all(wrs)).allIt( it.success )

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
  let saveas = "fmab_opening3.mkv"

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
    removeFile saveas
    wr = waitfor grid.downloadFile("fmab_opening3.mkv")
    check not wr.success # because no such file uploaded
    wr = waitfor grid.downloadFile(dwfile)
    wr.success.reasonedCheck("Grid download file", wr.reason)
    check fileExists(dwfile)
    wr = waitfor grid.downloadAs(dwfile, saveas)
    wr.success.reasonedCheck("Grid download as", wr.reason)
    check fileExists(saveas)

  test "GridStream operations":
    var f = openAsync(saveas)
    var gf = waitfor grid.getStream(bson({filename: dwfile}), buffered = true)
    check f.getFileSize == gf.fileSize
    check f.getFilePos == gf.getPosition

    let threekb = 3.kilobytes
    var bufread = waitfor f.read(threekb)
    var binread = waitfor gf.read(threekb)
    check bufread == binread
    check f.getFilePos == gf.getPosition

    let fivemb = 5.megabytes
    bufread = waitfor f.read(fivemb)
    binread = waitfor gf.read(fivemb)
    check bufread.len == binread.len

    # disabled at first because of too large string
    check bufread == binread 

    check f.getFilePos == gf.getPosition

    close f
    close gf

  test "List files":
    check insert5files(grid, filename)
    let filenames = waitfor grid.listFileNames()
    check filenames.len == 6
    check dwfile in filenames
    let newinserts = waitfor grid.listFileNames(matcher = bson({
      filename: { "$regex": """_\d\.mkv$""" }
    }).toBson)
    check newinserts.len == 5
    check dwfile notin newinserts

  test "Remove file(s)":
    # remove all files
    wr = waitfor grid.removeFile()
    check (waitfor grid.availableFiles) == 0
    wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
    check insert5files(grid, filename)

    # removing using regex
    wr = waitfor grid.removeFile(bson({
      filename: { "$regex": """_[23]\.mkv$""" }
    }).toBson)
    wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
    check (waitfor grid.availableFiles) == 3

    # removing not available file
    wr = waitfor grid.removeFile("there's no this file")
    wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
    check (waitfor grid.availableFiles) == 3

  test "Drop bucket":
    wr = waitfor grid.drop()
    wr.success.reasonedCheck("gridfs.drop error", wr.reason)

  test "Teardown db":
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