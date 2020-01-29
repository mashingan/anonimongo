
import wire
import bson
import pool

import sugar, times, oids, asyncfile
import mimetypes, os, strformat

{.hint[XDeclaredButNotUsed]: off.}
{.warning[UnusedImport]: off.}

proc acknowledgedInsert(s: Stream, data: BsonDocument,
    dbname = "temptest.$cmd", collname = "role"): int =
  let insertQuery = bson({
    insert: collname,
    documents: [data]
  })
  result = s.prepareQuery(0, 0, opQuery.int32, 0,
    dbname, 0, 1, insertQuery)

proc insert(s: AsyncSocket, data: BsonDocument, dbname = "temptest.$cmd", collname = "role"):
  Future[void] {.async.} =
  var ss = newStringStream()
  discard ss.acknowledgedInsert(data, collname = collname)
  await s.send ss.readAll
  let reply = await s.getReply
  dump reply
  look reply

proc insertedReply(s: AsyncSocket, data: BsonDocument, dbname = "temptest.$cmd",
  collname = "role"): Future[ReplyFormat]{.async.} =
  var ss = newStringStream()
  discard ss.acknowledgedInsert(data, collname = collname)
  await s.send ss.readAll
  result = await s.getReply

proc create(s: AsyncSocket, cmd: BsonDocument): Future[void] {.async.} =
  var ss = newStringStream()
  let dbname = "temptest"
  discard ss.prepareQuery(0, 0, opQuery.int32, 0, dbname & "$.cmd",
    0, 1, cmd)
  await s.send ss.readAll
  let reply = await s.getReply
  dump reply
  look reply
  #look(await s.getReply)
  #discard s.prepareQuery(id, 0, opQuery.int32, 0, dbname & ".$cmd",
  #  skip.int32, 1, findq)
  discard

proc createBucket(s: AsyncSocket, name: string, chunkSize: int32 = 255):
  Future[void] {.async.} =
  let
    buckf = name & ".files"
    buckc = name & ".chunks"
  let cmd = bson({
      create: buckf,
  })
  await s.create(cmd)
  let newcmd = bson({
    create: buckc,
  })
  await s.create(newcmd)

proc uploadFile(s: AsyncSocket, fname, buckname: string, chunkSize: int32 = 255):
    Future[void] {.async.} =
  let objid = genoid()
  let (_, filename, ext) = splitFile fname
  var f: AsyncFile
  try:
    f = openAsync fname
  except:
    echo getCurrentExceptionMsg()
    return
  defer: f.close()
  let fsize = f.getFileSize
  dump fsize
  let m = newMimetypes()
  let metadata = bson({
    mime: m.getMimetype(ext),
    ext: ext,
  })
  let (mlen, _) = encode metadata
  let length = 12 + 4 + 8 + filename.len + mlen
  var fileentry = bson({
    "_id": objid,
    length: fsize.int32,
    chunkSize: chunkSize,
    uploadDate: now().toTime,
    filename: filename & ext,
    metadata: {
      mime: m.getMimetype(ext),
      ext: ext,
    },
  })
  #let (length, _) = encode fileentry
  dump fileentry
  #fileentry["length"] = length
  #fileentry.encoded = false
  #dump fileentry
  var docs = (await s.insertedReply(fileentry, collname = buckname & ".files")).documents
  dump docs
  if docs.len > 1 and "errmsg" in docs[0]:
    let msg = docs[0]["errmsg"].get.ofString
    echo &"error insert files info: {msg}"
    return
  var chunkn = 0

  let buckc = buckname & ".chunks"
  dump buckc
  for _ in countup(0, int32(fsize-1), chunkSize):
    var b = bson({
      files_id: objid,
      n: chunkn,
    })
    dump b
    let binstr = await f.read(chunkSize)
    b["data"] = bsonBinary binstr
    docs = (await s.insertedReply(b, collname = buckc)).documents
    if docs.len > 1 and "errmsg" in docs[0]:
      let msg = docs[0]["errmsg"].get.ofString
      echo &"error insert chunk {chunkn} with msg: {msg}"
      return
    inc chunkn

proc iterate(docs: seq[BsonDocument], f: AsyncFile, currbatch, currsize: int):
  Future[(int, int)] {.async.} =
  result = (currbatch, currsize)
  for d in docs:
    if "cursor" in d and "firstBatch" in d["cursor"].get.ofEmbedded:
      result[0] += d["cursor"]["firstBatch"].ofArray.len
      dump result[0]
      for doc in d["cursor"]["firstBatch"].ofArray:
        let binstr = doc["data"].get.ofBinary.stringbytes
        result[1] += binstr.len
        await f.write(binstr)
    else:
      let binstr = d["data"].get.ofBinary.stringbytes
      result[1] += binstr.len
      await f.write(d["data"].get.ofBinary.stringbytes)

proc downloadFile(s: AsyncSocket, fname, buckname: string):
  Future[(AsyncFile, bool)]{.async.} =
  result = (nil, false)
  let sort = bson({n: 1.int32})
  let selector = bson({data: 1.int32, n: 1.int32})
  let buckf = buckname & ".files"
  dump buckf
  let (dirname, filename, extname) = splitFile fname
  var query = bson({filename: filename & extname})
  var reply = await s.queryAck(0, "temptest", buckname & ".files",
    query = query, sort = bson({"_id": (-1).int32}), limit = 1)

  dump query
  dump buckname
  dump reply
  if reply.numberReturned <= 0:
    echo &"no file found for {fname}"
    return
  var docs = reply.documents
  if "errmsg" in docs[0] or docs[0]["ok"].get.ofDouble.int != 1:
    let msg = docs[0]["errmsg"].get.ofString
    echo &"failed to retrieve file: {msg}"
    return
  let doc1 = docs[0]["cursor"]["firstBatch"][0]
  let fileid = doc1["_id"]
  let fsize: int32 = doc1["length"].get
  dump fsize
  query = bson({
    "files_id": fileid,
  })
  try:
    result[0] = openAsync(fname, fmReadWrite)
  except:
    echo getCurrentExceptionMsg()
    return
  var reply2 = await s.queryAck(0, "temptest", buckname & ".chunks",
    query, sort = sort, selector = selector)

  let cursorid = reply2.cursorId
  if reply2.numberReturned <= 0:
    close result[0]
    echo &"not found {fname}"
    return

  docs = reply2.documents
  var (fbatch, currsize) = await iterate(docs, result[0], 0, 0)

  dump currsize
  while currsize < fsize:
    echo &"still {currsize.float / fsize.float * 100}%"
    reply2 = await s.queryAck(0, "temptest", buckname & ".chunks",
      query, sort = sort, selector = selector, skip = fbatch)
    if reply2.numberReturned <= 0:
      break
    docs = reply2.documents
    (fbatch, currsize) = await iterate(docs, result[0], fbatch, currsize)
    dump currsize
  result[1] = true


when isMainModule:
  proc main {.async.} =
    let poolSize = 1
    #let loopsize = poolsize * 3
    let fname = "d:/downloads/fmab28_opening3.mkv"
    dump fname
    var pool = initPool(poolSize)
    waitFor pool.connect("localhost", 27017)
    defer: close pool
    let (cid, conn) = await pool.getConn
    let collname = "test_create_coll"
    let buckname = "test_bucket"
    let cmd = bson({
      create: collname,
      #capped: false,
      #autoIndexId: false,
    })
    let insertq = bson({
      fieldInt32: 0.int32,
      fieldInt64: 100.int64,
      createdAt: now().toTime,
    })
    #[
    # test creating and inserting the collection
    await conn.socket.create(cmd)
    await conn.socket.insert(insertq, collname = collname)
    ]#
    #[
    # test creating bucket and uploading file
    #await conn.socket.createBucket(buckname)
    #await conn.socket.uploadFile(fname, buckname, chunkSize = 1024 * 1024)
    #pool.endConn cid
    ]#
    let (_, filename, ext) = splitFile fname
    #let (f, success) = await conn.socket.downloadFile("." / (filename & ext), buckname)
    let (f, success) = await conn.socket.downloadFile(filename & ext, buckname)
    if success:
      #echo &"""success writing file {"./" / (filename & ext)}, now closing"""
      echo &"""success writing file {filename & ext}, now closing"""
      close f
    else:
      echo "some error happened and cannot download file"

  waitFor main()