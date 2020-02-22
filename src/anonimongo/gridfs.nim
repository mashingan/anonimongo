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
  else:
    result = WriteResult(success: true, kind: wkSingle)

proc uploadFile*(g: GridFS, filename: string, chunk = 0'i32, metadata = bson()):
  Future[WriteResult] {.async, discardable.} =
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