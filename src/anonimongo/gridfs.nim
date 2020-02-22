import strformat, strformat, asyncfile, oids, times, sequtils, os
import mimetypes

import dbops/[admmgmt]
import core/[bson, types, wire, utils]
import collections

func files(name: string): string = &"{name}.files"
func chunks(name: string): string = &"{name}.chunks"
func kilobytes*(n: Positive): int = n * 1024
func megabytes*(n: Positive): int = n * 1024.kilobytes

const verbose = defined(verbose)
const defaultChunkSize: int32 = 255 * 1024 # 255 KB

when verbose:
  import sugar

proc createBucket*(db: Database, name = "fs", chunkSize = defaultChunkSize):
  Future[GridFS] {.async.} =
  new result
  result.name = name
  result.chunkSize = chunkSize
  let collOp = [
    db.create(name.files),
    db.create(name.chunks)
  ]
  for wr in await all(collop):
    if not wr.success and wr.reason != "":
      raise newException(MongoError, &"createBucket error: {wr.reason}")
    elif not wr.success and wr.kind == wkMany and
      wr.errmsgs.len > 1:
      raise newException(MongoError,
        &"""createBucket error: {wr.errmsgs.join("\n")}""")
  
  result.files = db[name.files]
  result.chunks = db[name.chunks]
  discard await all([
    result.files.createIndex(bson({ filename: 1, uploadDate: 1 })),
    result.chunks.createIndex(bson({ files_id: 1, n: 1 }))
  ])

proc createBucket*(c: Collection, name = "fs", chunkSize = defaultChunkSize):
  Future[GridFS] {.async.} =
  result = await c.db.createBucket(name, chunkSize)

proc getBucket*(db: Database, name = "fs"): Future[GridFS]{.async.} =
  new result
  result.name = name
  result.files = db[name.files]
  result.chunks = db[name.chunks]
  let foundChunk = await result.files.findOne(projection = bson({
    chunkSize: 1
  }))
  if not foundChunk.isNil:
    result.chunkSize = foundChunk["chunkSize"]
  else:
    result.chunkSize = defaultChunkSize

proc getBucket*(c: Collection, name = "fs"): Future[GridFS]{.async.} =
  result = await c.db.getBucket(name)

proc uploadFile*(g: GridFS, f: AsyncFile, filename = "",
  chunk = 0'i32, metadata = bson()):
  Future[WriteResult]{.async.} =
  let foid = genoid()
  let fsize = getFileSize f
  let chunkSize = if chunk == 0: g.chunkSize else: chunk
  var fileentry = bson({
    "_id": foid,
    "chunkSize": chunkSize,
    "length": fsize,
    "uploadDate": now().toTime,
    "filename": filename,
  })
  fileentry.addOptional("metadata", metadata)
  let status = await g.files.insert(@[fileentry])
  if not status.success:
    if verbose:
      if status.reason != "":
        echo &"uploadFile failed: {status.reason}"
      elif status.kind == wkMany and status.errmsgs.len > 0:
        echo &"""uploadFile failed: {status.errmsgs.join("\n")}"""
    result = status
    return

  var chunkn = 0
  # curread is needed because each of inserting documents only
  # available less and equal of the capsize 16 megabyes.
  # Since insert able to accept seq[BsonDocument] hence we hold
  # the actual insert before the curread exceeds capsize.
  var curread = 0
  let capsize = 16.megabytes
  var insertops = newseq[Future[WriteResult]]()
  var chunks = newseq[BsonDocument]()
  for _ in countup(0, int(fsize-1), chunksize):
    var chunk = bson({
      "files_id": foid,
      "n": chunkn
    })
    let data = await f.read(chunksize)
    chunk["data"] = bsonBinary data
    let newcurr = curread + data.len
    if newcurr >= capsize:
      curread = data.len
      insertops.add g.chunks.insert(chunks)
      chunks = @[chunk]
    else:
      curread = newcurr
      chunks.add chunk
    inc chunkn
  # inserting the left-over
  if chunks.len > 0: insertops.add g.chunks.insert(chunks)
  if anyIt(await all(insertops), not it.success):
    echo "uploadFile failed: some error happened " &
      "when uploading. Cancel it"
    # remove all inserted file info and chunks
    discard await all([
      g.files.remove(bson({ "_id": foid })),
      g.chunks.remove(bson({ files_id: foid }))
    ])
    result = WriteResult(kind: wkSingle,
      reason: "error when writing chunks' file")
  else:
    result = WriteResult(success: true, kind: wkSingle)

proc uploadFile*(g: GridFS, filename: string, chunk = 0'i32,
  metadata = bson()): Future[WriteResult] {.async, discardable.} =
  ## A higher uploadFile which directly open and close file from filename.
  var f: AsyncFile
  try:
    f = openAsync filename
  except IOError:
    echo getCurrentExceptionMsg()
    return
  defer: close f
  let chunksize = if chunk == 0: g.chunkSize else: chunk
  
  let (_, fname, ext) = splitFile filename
  let m = newMimeTypes()
  var filemetadata = metadata
  if not filemetadata.isNil:
    filemetadata["mime"] = m.getMimeType(ext).toBson
    filemetadata["ext"] = ext.toBson
  else:
    filemetadata = bson({
      "mime": m.getMimeType(ext),
      "exit": ext
    })
  result = await g.uploadFile(f, fname & ext,
    metadata = filemetadata, chunk = chunksize)

proc downloadFile*(g: GridFS, f: AsyncFile, filename = ""):
  Future[WriteResult] {.async, discardable.} =
  ## Download given filename and write it to f asyncfile. This only download
  ## the latest uploaded file in the same name.
  let q = bson({ "filename": filename })
  let uploadDesc = bson({ "uploadDate": -1 })
  let fields = bson({"_id": 1, "length": 1 })
  let fdata = await g.files.findOne(q, projection = fields, sort = uploadDesc)
  when verbose: dump fdata
  if fdata.isNil: # fdata empty
    let reason = &"cannot find {filename}: {$fdata}."
    if verbose:
      echo reason
    result = WriteResult(kind: wkSingle, reason: reason)
    return

  let qchunk = bson({ "files_id": fdata["_id"] })
  let fsize = fdata["length"].ofInt
  let selector = bson({ "data": 1 })
  let sort = bson({ "n": 1 })
  var currsize = 0
  for chunk in await g.chunks.findIter(qchunk, selector, sort):
    let data = chunk["data"].ofBinary.stringbytes
    currsize += data.len
    await f.write(data)

  if currsize < fsize:
    result = WriteResult(
      kind: wkSingle,
      reason: "Incomplete file download; only at " &
        &"{currsize.float / fsize.float * 100}%")
    return
  result = WriteResult(
    success: true,
    kind: wkSingle)

proc downloadFile*(bucket: GridFS, filename: string):
  Future[WriteResult]{.async, discardable.} =
  ## Higher version for downloadFile. Ensure the destination file path has
  ## writing permission
  var f: AsyncFile
  try:
    f = openAsync(filename, fmWrite)
  except IOError:
    echo getCurrentExceptionMsg()
    return
  defer: close f
  let (_, fname, ext) = splitFile filename
  result = await bucket.downloadFile(f,  fname & ext)