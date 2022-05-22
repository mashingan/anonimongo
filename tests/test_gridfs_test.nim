import unittest, os, osproc, strformat, sequtils, asyncfile
import sugar
import anonimongo
import utils_test

{.warning[UnusedImport]: off.}

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

if filename != "" and saveas != "":
  suite "GridFS implementation tests":
    
    test "Mongo server is running":
      if runlocal:
        require mongorun.running
      else:
        skip()

    var mongo: Mongo[AsyncSocket]
    var grid: GridFS[AsyncSocket]
    var db: Database[AsyncSocket]
    var wr: WriteResult
    let dbname = "newtemptest"
    let (_, fname, ext) = splitFile filename
    let dwfile = fname & ext

    test "Connect to localhost and authentication":
      mongo = testsetup()
      require(mongo != nil)
      if mongo.withAuth:
        require(mongo.authenticated)
      db = mongo[dbname]

    test "Drop database first in case of error in previous test":
      require db != nil
      wr = waitFor db.dropDatabase
      wr.success.reasonedCheck("dropDatabase error", wr.reason)

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
      wr = waitfor grid.downloadFile(saveas)
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
      f.setFilePos fivemb
      waitfor gf.setPosition fivemb
      check f.getFilePos == gf.getPosition

      bufread = waitfor f.read(fivemb)
      binread = waitfor gf.read(fivemb)
      check bufread.len == binread.len
      check bufread == binread 
      check f.getFilePos == gf.getPosition

      close f
      close gf

    test "Gridstream read chunked size":
      let chunkfile = "gs_chunks.mkv"
      var gf = waitfor grid.getStream(bson({filename: dwfile}))
      var f = openAsync(chunkfile, fmWrite)
      var curread = 0
      while curread < gf.fileSize:
        var data = waitfor gf.read(1500.kilobytes)
        curread += data.len
        waitfor f.write(data)
      check f.getFileSize == gf.fileSize
      check gf.getPosition == gf.fileSize-1
      close gf
      close f
      removeFile chunkfile

    test "List files":
      check insert5files(grid, filename)
      let filenames = waitfor grid.listFileNames()
      check filenames.len == 6
      check dwfile in filenames
      let (_, _, fileext) = splitFile filename
      let newinserts = waitfor grid.listFileNames(matcher = bson({
        filename: { "$regex": fmt"""_\d\{fileext}$""" }
      }).toBson)
      check newinserts.len == 5
      check dwfile notin newinserts

    test "Remove file(s)":
      # remove all files
      wr = waitfor grid.removeFile()
      check (waitfor grid.availableFiles) == 0
      check (waitfor grid.chunks.count()) == 0
      wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
      check insert5files(grid, filename)

      # removing using regex
      let (_, _, ext) = splitFile filename
      wr = waitfor grid.removeFile(bson({
        filename: { "$regex": fmt"""_[23]\{ext}$""" }
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