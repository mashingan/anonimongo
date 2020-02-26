import strformat, strformat, asyncfile, oids, times, sequtils, os
import mimetypes, sugar

import dbops/[admmgmt]
import core/[bson, types, wire, utils]
import collections

func files(name: string): string = &"{name}.files"
func chunks(name: string): string = &"{name}.chunks"
func kilobytes*(n: Positive): int = n * 1024
func megabytes*(n: Positive): int = n * 1024.kilobytes

const verbose = defined(verbose)
const defaultChunkSize: int32 = 255 * 1024 # 255 KB
const gridEnsured = defined(gridEnsured)

proc createBucket*(db: Database, name = "fs", chunkSize = defaultChunkSize):
  Future[GridFS] {.async.} =
  ## By default it's using string "fs" for bucket name with default chunk
  ## size for file is 255 KB. The chunk size can be override for each
  ## uploadFile but by default will using the defined gridfs chunk size.
  ## As mentioned in Mongo spec, each collection has its own indexes i.e
  ## <bucketname>.files has index `{ filename: 1, uploadData: 1 }`
  ## <bucketname>.chunks has index `{ files_id: 1, n: 1 }`.
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
  ## Collection version to create bucket. Offload the actual operation to
  ## gridfs.createBucket(database).
  result = await c.db.createBucket(name, chunkSize)

proc getBucket*(db: Database, name = "fs"): Future[GridFS]{.async.} =
  ## Get bucket from existing database. If the bucket is not available,
  ## Mongo will implicitly create the files and chunks collections but
  ## without the necessary indexes.
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

when gridEnsured:
  proc ensureIndex(g: GridFS) {.async.} =
    let indexes = await all([g.files.listIndexes(), g.chunks.listIndexes()])
    var idxops = newseq[Future[WriteResult]](2)
    if not indexes[0].anyIt( it["name"] == "filename_1_uploadDate_1_" ):
      idxops[0] = g.files.createIndex(bson({ filename: 1, uploadDate: 1 }))
    if not indexes[1].anyIt( it["name"] == "files_id_1_n_1_1" ):
      idxops[1] = g.chunks.createIndex(bson({ files_id: 1, n: 1 }))
    discard await idxops.all

proc getBucket*(c: Collection, name = "fs"): Future[GridFS]{.async.} =
  result = await c.db.getBucket(name)
  when gridEnsured: await result.ensureIndex

proc uploadFile*(g: GridFS, f: AsyncFile, filename = "", chunk = 0'i32,
  metadata = bson()): Future[WriteResult]{.async.} =
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

template prepareFile(target: string, mode = fmRead): untyped {.dirty.} =
  var f: AsyncFile
  try:
    f = openAsync(target, mode)
  except IOError:
    result = WriteResult(
      reason: getCurrentExceptionMsg(),
      kind: wkSingle)
    when verbose: dump result.reason
    return
  defer: close f

proc uploadFile*(g: GridFS, filename: string, chunk = 0'i32,
  metadata = bson()): Future[WriteResult] {.async, discardable.} =
  ## A higher uploadFile which directly open and close file from filename.
  prepareFile(filename)
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
      "ext": ext
    })
  result = await g.uploadFile(f, fname & ext,
    metadata = filemetadata, chunk = chunksize)

proc downloadFile*(g: GridFS, f: AsyncFile, filename = ""):
  Future[WriteResult] {.async, discardable.} =
  ## Download given filename and write it to f asyncfile. This only download
  ## the latest uploaded file in the same name.
  when gridEnsured: await g.ensureIndex
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
  prepareFile(filename, fmWrite)
  let (_, fname, ext) = splitFile filename
  result = await bucket.downloadFile(f,  fname & ext)

proc downloadAs*(g: GridFS, source, target: string): Future[WriteResult]
  {.async.} =
  ## To download file as different file name.
  prepareFile(target, fmWrite)
  result = await g.downloadFile(f, source)

proc availableFiles*(g: GridFS, query = bson()): Future[int] {.async.} =
  result = await g.files.count(query)

template prepareMatcher(m: BsonBase): untyped =
  var q = bson()
  if  m.kind == bkString and m != "all":
    q["filename"] = m
  elif m.kind == bkEmbed and "filename" in m:
    q = m
  elif m.kind == bkEmbed:
    q["filename"] = m
  q

proc listFileNames*(g: GridFS, matcher = "all".toBson, sort = bson()):
  Future[seq[string]]{.async.} =
  ## Retrieve available list filenames given matcher Bson.
  ## By default the matcher is BsonString "all" which return
  ## all available names. Sort to choose the order which
  ## criteria it's should be first/last. The matcher is elaborated
  ## explained `removeFile`_ as it's using the same mechanism.
  ##
  ## .. _removeFile: #removeFile,GridFS,BsonBase,bool
  when verbose: dump matcher
  var q = matcher.prepareMatcher
  let projection = bson({ filename: 1 })
  var fileslen = await g.files.count(q)
  result = newseq[string](fileslen)
  for i, doc in await g.files.findIter(q, projection, sort):
    result[i] = doc["filename"]
  when verbose: dump result

template foldWMany(a, b: untyped): untyped =
  WriteResult(
    success: a.success and b.success,
    n: a.n + b.n,
    kind: wkMany,
    reason: &"{a.reason}, {b.reason}",
    errmsgs: concat(a.errmsgs, b.errmsgs))

template foldWSingle(a, b: untyped): untyped =
  WriteResult(
    success: a.success and b.success,
    kind: wkSingle,
    reason: &"{a.reason}, {b.reason}")

proc wrNop: Future[WriteResult]{.async.} =
  result = WriteResult( success: true, kind: wkMany)

proc removeFile*(g: GridFS, matcher = "all".toBson, one = false):
  Future[WriteResult]{.async.} =
  ## Remove available files that match with matcher. By default the matcher
  ## is BsonString "all" which remove all files. If it's not "all" and
  ## BsonString, it's matched for the filename and for specific finding,
  ## matcher can use the regex string e.g.
  ##
  ## .. code-block:: Nim
  ##
  ##    matcher = bson({
  ##      filename: { "regex": """_\d\.mkv$""" }
  ##    })
  ##
  ## which looking for any filename that match the pattern i.e.
  ##
  ## - "any_filename_but_aslong_have_1.mkv"
  ## - "this is ok too_2.mkv"
  ## - "also this is ok_3.mkv"
  ##
  ## For example removing all mkv files, the matcher would be
  ##
  ## .. code-block:: Nim
  ##
  ##    matcher = bson({ metadata: { ext: "mkv" }})
  ##
  ##
  let projection = bson({ filename: 1 })
  var qfiles = bson()
  var cfiles: seq[BsonDocument]
  var all = true
  if (matcher.kind == bkString and matcher != "all") or matcher.kind == bkEmbed:
    all = false
    qfiles = prepareMatcher matcher
    cfiles = await g.files.findAll(qfiles, projection)
    cfiles.apply((d: var BsonDocument) => (d = bson({ files_id: d["_id"] })))
  var ops = newseq[Future[WriteResult]](2)
  ops[0] = g.files.remove(qfiles, one)
  if cfiles.len == 0 and not all:
    # literally no operation
    ops[1] = wrNop()
  elif cfiles.len == 0:
    # delete all
    ops[1] = g.chunks.remove(bson())
  else:
    ops[1] = g.chunks.remove(cfiles)
  result = (await all(ops)).foldl(foldWMany(a, b))

proc drop*(g: GridFS): Future[WriteResult]{.async.} =
  ## Drop the current bucket name.
  result = foldl(await all([
    g.files.drop(), g.chunks.drop()
  ]), foldWSingle(a, b))

type
  FileInfo = object
    id: Oid
    chunkSize: int32
    length: int64
    uploadDate: Time
    filename: string
    metadata: BsonDocument

  DataStream = object
      files_id: Oid
      n: int
      data: string ## bytes

  GridStream* = ref object of RootObj
    grid: GridFS
    filename: string
    buffered: bool
    buffer: seq[BsonDocument]
    isClosed: bool
    info: FileInfo
    data: DataStream
    pos: int64
    point: int

func currchunk(gs: GridStream): int = gs.data.n * gs.info.chunkSize
func fileSize*(gs: GridStream): int64 = gs.info.length

proc final(gs: GridStream) =
  gs.isClosed = true

proc close*(gs: GridStream) =
  gs.isClosed = true

proc fetchData(gs: GridStream, chunkn: int) {.async.} =
  var data: BsonDocument
  if gs.buffered and not gs.buffer[chunkn].isNil:
    data = gs.buffer[chunkn]
  else:
    data = await gs.grid.chunks.findOne(bson({
      files_id: gs.info.id, n: chunkn }))
  if gs.buffered: gs.buffer[chunkn] = data
  gs.data = data.to DataStream

func within(targetpos, chunkpos, chunksize: int64): bool =
  targetpos >= chunkpos and targetpos < (chunkpos + chunksize)

proc setPosition*(gs: GridStream, pos: int64, chunkn = -1) {.async.} =
  if pos >= gs.info.length:
    gs.pos = pos-1
  else:
    gs.pos = pos
  gs.point = (gs.pos mod gs.info.chunkSize).int
  let currchunk: int = gs.currchunk
  if not pos.within(currchunk, gs.info.chunkSize):
    let targetchunk = if chunkn == -1: gs.pos div gs.info.chunkSize
                      else: chunkn
    await gs.fetchData(targetchunk.int)

func getPosition*(gs: GridStream): int64 = gs.pos

proc read*(gs: GridStream, length = 0'i64): Future[string] {.async.} =
  if length == 0:
    return
  var reslen = length
  if (gs.pos + reslen) >= gs.info.length:
    reslen = int(gs.info.length - gs.pos)
  result = newstring reslen

  if (gs.pos + reslen).within(gs.currchunk, gs.info.chunkSize):
    for i in 0 ..< reslen: result[i] = gs.data.data[gs.point + i]
    gs.point += reslen.int
    gs.pos += reslen
  else:
    var curread = 0'i64
    while curread < reslen:
      #let databuflen = gs.info.chunkSize - gs.point
      let databuflen = gs.data.data.len - gs.point
      let toread = min(databuflen, reslen-curread)
      for i in 0 ..< toread:
        result[curread+i] = gs.data.data[gs.point + i]
      curread += toread
      await gs.setPosition(gs.pos + toread, gs.data.n + 1)

proc readAll*(gs: GridStream): Future[string] {.async.} =
  let length = gs.info.length - gs.pos
  result = await gs.read(length)

proc getStream*(g: GridFS, matcher: BsonBase, sort = bson(),
  buffered = false): Future[GridStream]{.async.} =
  new(result, final)
  result.grid = g
  result.buffered = buffered
  let q = prepareMatcher matcher
  when verbose: dump q
  let bsinfo = await g.files.findOne(q, sort = sort)
  if bsinfo.isNil or bsinfo.len == 0:
    raise newException(MongoError,
      &"Cannot find any file that match {matcher}")
  when verbose: dump bsinfo
  result.info = bsinfo.to FileInfo
  result.info.id = bsinfo["_id"]
  if buffered:
    result.buffer = newseq[BsonDocument](await g.chunks.count(
      bson({ files_id: result.info.id })))
  await result.fetchData(0)