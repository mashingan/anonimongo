import unittest, os, osproc, strformat, sequtils, asyncfile
import sugar
import anonimongo
import utils_test

{.warning[UnusedImport]: off.}

proc insert5files(g: GridFS[TheSock], fname: string): bool =
  var f: AsyncFile
  try:
    f = openAsync(fname)
  except:
    echo getCurrentExceptionMsg()
    return
  defer: close f
  let (_, thename, ext) = splitFile fname
  when anoSocketSync:
    var wrs = newseq[WriteResult](5)
  else:
    var wrs = newseq[Future[WriteResult]](5)
  for i in 0 .. wrs.high:
    let newname = &"{thename}_{i}{ext}"
    wrs[i] = g.uploadFile(f, newname)
  when anoSocketSync:
    wrs.allIt( it.success )
  else:
    (waitfor all(wrs)).allIt( it.success )

if filename != "" and saveas != "":
  dump filename
  dump saveas
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

    var mongo: Mongo[TheSock]
    var grid: GridFS[TheSock]
    var db: Database[TheSock]
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
      when anoSocketSync:
        wr = db.dropDatabase
      else:
        wr = waitFor db.dropDatabase
      wr.success.reasonedCheck("dropDatabase error", wr.reason)

    test "Create default bucket":
      require db != nil
      when anoSocketSync:
        grid = db.createBucket(chunkSize = 1.megabytes.int32)
      else:
        grid = waitfor db.createBucket(chunkSize = 1.megabytes.int32)
      require grid != nil

    test "Upload file":
      when anoSocketSync:
        wr = grid.uploadFile(filename)
      else:
        wr = waitfor grid.uploadFile(filename)
      wr.success.reasonedCheck("Grid upload file", wr.reason)

    test "Download file":
      removeFile dwfile
      removeFile saveas
      when anoSocketSync:
        wr = grid.downloadFile(saveas)
      else:
        wr = waitfor grid.downloadFile(saveas)
      check not wr.success # because no such file uploaded
      when anoSocketSync:
        wr = grid.downloadFile(dwfile)
      else:
        wr = waitfor grid.downloadFile(dwfile)
      wr.success.reasonedCheck("Grid download file", wr.reason)
      check fileExists(dwfile)
      when anoSocketSync:
        wr = grid.downloadAs(dwfile, saveas)
      else:
        wr = waitfor grid.downloadAs(dwfile, saveas)
      wr.success.reasonedCheck("Grid download as", wr.reason)
      check fileExists(saveas)

    test "GridStream operations":
      var f = openAsync(saveas)
      when anoSocketSync:
        var gf = grid.getStream(bson({filename: dwfile}), buffered = true)
      else:
        var gf = waitfor grid.getStream(bson({filename: dwfile}), buffered = true)
      check f.getFileSize == gf.fileSize
      check f.getFilePos == gf.getPosition

      let threekb = 3.kilobytes
      when anoSocketSync:
        var binread = gf.read(threekb)
      else:
        var binread = waitfor gf.read(threekb)
      var bufread = waitfor f.read(threekb)
      check bufread == binread
      check f.getFilePos == gf.getPosition

      let fivemb = 5.megabytes
      f.setFilePos fivemb
      when anoSocketSync:
        gf.setPosition fivemb
      else:
        waitfor gf.setPosition fivemb
      check f.getFilePos == gf.getPosition

      when anoSocketSync:
        binread = gf.read(fivemb)
      else:
        binread = waitfor gf.read(fivemb)
      bufread = waitfor f.read(fivemb)
      check bufread.len == binread.len
      check bufread == binread 
      check f.getFilePos == gf.getPosition

      close f
      close gf

    test "Gridstream read chunked size":
      let chunkfile = "gs_chunks.mkv"
      when anoSocketSync:
        var gf = grid.getStream(bson({filename: dwfile}))
      else:
        var gf = waitfor grid.getStream(bson({filename: dwfile}))
      var f = openAsync(chunkfile, fmWrite)
      var curread = 0
      while curread < gf.fileSize:
        when anoSocketSync:
          var data = gf.read(1500.kilobytes)
        else:
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
      when anoSocketSync:
        let filenames = grid.listFileNames()
      else:
        let filenames = waitfor grid.listFileNames()
      check filenames.len == 6
      check dwfile in filenames
      let (_, _, fileext) = splitFile filename
      when anoSocketSync:
        let newinserts = grid.listFileNames(matcher = bson({
          filename: { "$regex": fmt"""_\d\{fileext}$""" }
        }).toBson)
      else:
        let newinserts = waitfor grid.listFileNames(matcher = bson({
          filename: { "$regex": fmt"""_\d\{fileext}$""" }
        }).toBson)
      check newinserts.len == 5
      check dwfile notin newinserts

    test "Remove file(s)":
      # remove all files
      when anoSocketSync:
        wr = grid.removeFile()
        check grid.availableFiles == 0
        check grid.chunks.count() == 0
      else:
        wr = waitfor grid.removeFile()
        check (waitfor grid.availableFiles) == 0
        check (waitfor grid.chunks.count()) == 0
      wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
      check insert5files(grid, filename)

      # removing using regex
      let (_, _, ext) = splitFile filename
      when anoSocketSync:
        wr = grid.removeFile(bson({
          filename: { "$regex": fmt"""_[23]\{ext}$""" }
        }).toBson)
        wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
        check grid.availableFiles == 3

        # removing not available file
        wr = grid.removeFile("there's no this file")
        wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
        check grid.availableFiles == 3
      else:
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
      when anoSocketSync:
        wr = grid.drop()
      else:
        wr = waitfor grid.drop()
      wr.success.reasonedCheck("gridfs.drop error", wr.reason)

    test "Teardown db":
      require db != nil
      when anoSocketSync:
        wr = db.dropDatabase
      else:
        wr = waitFor db.dropDatabase
      wr.success.reasonedCheck("dropDatabase error", wr.reason)

    test "Shutdown mongo":
      if runlocal:
        require mongo != nil
        when anoSocketSync:
          wr = mongo.shutdown(timeout = 10)
        else:
          wr = waitFor mongo.shutdown(timeout = 10)
        check wr.success
      else:
        skip()

    close mongo
    if runlocal:
      if mongorun != nil and mongorun.running: kill mongorun
      close mongorun