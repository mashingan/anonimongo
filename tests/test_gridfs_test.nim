discard """
  
  action: "run"
  exitcode: 0
  
  # flags with which to run the test, delimited by `;`
  matrix: "-d:anostreamable -d:danger"
"""

from std/os import sleep, splitFile, removeFile, fileExists
from std/osproc import Process, kill, running, close
from std/strformat import `&`, fmt
from std/asyncfile import AsyncFile, close, openAsync, write,
  getFilePos, getFileSize, read, setFilePos
from std/sugar import dump
from std/sequtils import allIt

import ./utils_test

import anonimongo

const nim164up = (NimMajor, NimMinor, NimPatch) >= (1, 6, 4)
when nim164up:
  from std/exitprocs import addExitProc

proc insert5files(g: GridFS[TheSock], fname: string): bool =
  var f: AsyncFile
  try:
    f = openAsync(fname)
  except CatchableError:
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

  proc processKiller {.noconv.} =
    if runlocal:
      if mongorun.running: kill mongorun
      close mongorun

  when nim164up:
    addExitProc processKiller
  else:
    addQuitProc processKiller

  block: # "GridFS implementation tests":
    block: # "Mongo server is running":
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

    block: # "Connect to localhost and authentication":
      mongo = testsetup()
      require(mongo != nil)
      if mongo.withAuth:
        require(mongo.authenticated)
      db = mongo[dbname]

    block: # "Drop database first in case of error in previous test":
      require db != nil
      when anoSocketSync:
        wr = db.dropDatabase
      else:
        wr = waitFor db.dropDatabase
      wr.success.reasonedCheck("dropDatabase error", wr.reason)

    block: # "Create default bucket":
      require db != nil
      when anoSocketSync:
        grid = db.createBucket(chunkSize = 1.megabytes.int32)
      else:
        grid = waitfor db.createBucket(chunkSize = 1.megabytes.int32)
      require grid != nil

    block: # "Upload file":
      when anoSocketSync:
        wr = grid.uploadFile(filename)
      else:
        wr = waitfor grid.uploadFile(filename)
      wr.success.reasonedCheck("Grid upload file", wr.reason)

    block: # "Download file":
      removeFile dwfile
      removeFile saveas
      when anoSocketSync:
        wr = grid.downloadFile(saveas)
      else:
        wr = waitfor grid.downloadFile(saveas)
      assert not wr.success # because no such file uploaded
      when anoSocketSync:
        wr = grid.downloadFile(dwfile)
      else:
        wr = waitfor grid.downloadFile(dwfile)
      wr.success.reasonedCheck("Grid download file", wr.reason)
      assert fileExists(dwfile)
      when anoSocketSync:
        wr = grid.downloadAs(dwfile, saveas)
      else:
        wr = waitfor grid.downloadAs(dwfile, saveas)
      wr.success.reasonedCheck("Grid download as", wr.reason)
      assert fileExists(saveas)

    block: # "GridStream operations":
      var f = openAsync(saveas)
      when anoSocketSync:
        var gf = grid.getStream(bson({filename: dwfile}), buffered = true)
      else:
        var gf = waitfor grid.getStream(bson({filename: dwfile}), buffered = true)
      assert f.getFileSize == gf.fileSize
      assert f.getFilePos == gf.getPosition

      let threekb = 3.kilobytes
      when anoSocketSync:
        var binread = gf.read(threekb)
      else:
        var binread = waitfor gf.read(threekb)
      var bufread = waitfor f.read(threekb)
      assert bufread == binread
      assert f.getFilePos == gf.getPosition

      let fivemb = 5.megabytes
      f.setFilePos fivemb
      when anoSocketSync:
        gf.setPosition fivemb
      else:
        waitfor gf.setPosition fivemb
      assert f.getFilePos == gf.getPosition

      when anoSocketSync:
        binread = gf.read(fivemb)
      else:
        binread = waitfor gf.read(fivemb)
      bufread = waitfor f.read(fivemb)
      assert bufread.len == binread.len
      assert bufread == binread 
      assert f.getFilePos == gf.getPosition

      close f
      close gf

    block: # "Gridstream read chunked size":
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
      assert f.getFileSize == gf.fileSize
      assert gf.getPosition == gf.fileSize-1
      close gf
      close f
      removeFile chunkfile

    block: # "List files":
      assert insert5files(grid, filename)
      when anoSocketSync:
        let filenames = grid.listFileNames()
      else:
        let filenames = waitfor grid.listFileNames()
      assert filenames.len == 6
      assert dwfile in filenames
      let (_, _, fileext) = splitFile filename
      when anoSocketSync:
        let newinserts = grid.listFileNames(matcher = bson({
          filename: { "$regex": fmt"""_\d\{fileext}$""" }
        }).toBson)
      else:
        let newinserts = waitfor grid.listFileNames(matcher = bson({
          filename: { "$regex": fmt"""_\d\{fileext}$""" }
        }).toBson)
      assert newinserts.len == 5
      assert dwfile notin newinserts

    block: # "Remove file(s)":
      # remove all files
      when anoSocketSync:
        wr = grid.removeFile()
        assert grid.availableFiles == 0
        assert grid.chunks.count() == 0
      else:
        wr = waitfor grid.removeFile()
        assert (waitfor grid.availableFiles) == 0
        assert (waitfor grid.chunks.count()) == 0
      wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
      assert insert5files(grid, filename)

      # removing using regex
      let (_, _, ext) = splitFile filename
      when anoSocketSync:
        wr = grid.removeFile(bson({
          filename: { "$regex": fmt"""_[23]\{ext}$""" }
        }).toBson)
        wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
        assert grid.availableFiles == 3

        # removing not available file
        wr = grid.removeFile("there's no this file")
        wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
        assert grid.availableFiles == 3
      else:
        wr = waitfor grid.removeFile(bson({
          filename: { "$regex": fmt"""_[23]\{ext}$""" }
        }).toBson)
        wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
        assert (waitfor grid.availableFiles) == 3

        # removing not available file
        wr = waitfor grid.removeFile("there's no this file")
        wr.success.reasonedCheck("gridfs.removeFile error", wr.reason)
        assert (waitfor grid.availableFiles) == 3

    block: # "Drop bucket":
      when anoSocketSync:
        wr = grid.drop()
      else:
        wr = waitfor grid.drop()
      wr.success.reasonedCheck("gridfs.drop error", wr.reason)

    block: # "Teardown db":
      require db != nil
      when anoSocketSync:
        wr = db.dropDatabase
      else:
        wr = waitFor db.dropDatabase
      wr.success.reasonedCheck("dropDatabase error", wr.reason)

    block: # "Shutdown mongo":
      if runlocal:
        require mongo != nil
        when anoSocketSync:
          wr = mongo.shutdown(timeout = 10)
        else:
          wr = waitFor mongo.shutdown(timeout = 10)
        assert wr.success
      else:
        skip()

    close mongo