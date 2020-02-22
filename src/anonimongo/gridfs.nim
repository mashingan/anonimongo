import strformat, strformat, asyncfile, oids, times, sequtils

import dbops/[admmgmt]
import core/[bson, types, wire, utils]
import collections

func files(name: string): string = &"{name}.files"
func chunks(name: string): string = &"{name}.chunks"
func kilobytes(n: Positive): int = n * 1024
func megabytes(n: Positive): int = n * 1024.kilobytes

const defaultChunkSize: int32 = 255 * 1024 # 255 KB

proc createBucket*(c: Collection, name = "fs", chunkSize = defaultChunkSize):
  Future[GridFS] {.async.} =
  new result
  result.name = name
  result.chunkSize = chunkSize
  let collOp = [
    c.db.create(name.files),
    c.db.create(name.chunks)
  ]
  for wr in await all(collop):
    if not wr.success and wr.reason != "":
      raise newException(MongoError, &"createBucket error: {wr.reason}")
    elif not wr.success and wr.kind == wkMany and
      wr.errmsgs.len > 1:
      raise newException(MongoError,
        &"""createBucket error: {wr.errmsgs.join("\n")}""")
  
  result.files = c.db[name.files]
  result.chunks = c.db[name.chunks]
  discard await all([
    result.files.createIndex(bson({ filename: 1, uploadDate: 1 })),
    result.chunks.createIndex(bson({ files_id: 1, n: 1 }))
  ])

proc getBucket*(c: Collection, name: string): Future[GridFS]{.async.} =
  new result
  result.name = name
  result.files = c.db[name.files]
  result.chunks = c.db[name.chunks]
  let foundChunk = await result.files.findOne(projection = bson({
    chunkSize: 1
  }))
  if not foundChunk.isNil:
    result.chunkSize = foundChunk["chunkSize"]
  else:
    result.chunkSize = defaultChunkSize

proc uploadFile*(g: GridFS, f: AsyncFile, filename = "",
  chunkSize = defaultChunkSize, metadata = bson()):
  Future[bool]{.async.} =
  let foid = genoid()
  let fsize = getFileSize f
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
    if status.reason != "":
      echo &"uploadFile failed: {status.reason}"
    elif status.kind == wkMany and status.errmsgs.len > 0:
      echo &"""uploadFile failed: {status.errmsgs.join("\n")}"""

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
  if anyIt(await all(insertops), not it.success):
    echo "uploadFile failed: some error happened " &
      "when uploading. Cancel it"
    # remove all inserted file info and chunks
    discard await all([
      g.files.remove(bson({ "_id": foid })),
      g.chunks.remove(bson({ files_id: foid }))
    ])
  else:
    result = true
