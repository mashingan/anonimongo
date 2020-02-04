import streams, strformat
import asyncdispatch, asyncnet
from sugar import dump
import bson

export streams, asyncnet, asyncdispatch

type
  OpCode* = enum
    opReply = 1'i32
    opUpdate = 2001'i32
    opInsert opReserved opQuery opGetMore opDelete opKillCursors
    opCommand = 2010'i32
    opCommandReply
    opMsg = 2013'i32

  MsgHeader* = object
    messageLength*, requestId*, responseTo*, opCode*: int32

  ReplyFormat* = object
    responseFlags*: int32
    cursorId*: int64
    startingFrom*: int32
    numberReturned*: int32
    documents*: seq[BsonDocument]

proc serialize(s: Stream, doc: BsonDocument): int =
  let (doclen, docstr) = encode doc
  result = doclen
  s.write docstr

proc msgHeader(s: Stream, reqId, returnTo, opCode: int32): int=
  result = 16
  s.write 0'i32
  s.writeLE reqId
  s.writeLE returnTo
  s.writeLE opCode

proc msgHeaderFetch(s: Stream): MsgHeader =
  MsgHeader(
    messageLength: s.readIntLE int32,
    requestId: s.readIntLE int32,
    responseTo: s.readIntLE int32,
    opCode: s.readIntLE int32
  )

proc replyParse*(s: Stream): ReplyFormat =
  result = ReplyFormat(
    responseFlags: s.readIntLE int32,
    cursorId: s.readIntLE int64,
    startingFrom: s.readIntLE int32,
    numberReturned: s.readIntLE int32
  )
  result.documents = newSeq[BsonDocument](result.numberReturned)
  for i in 0 ..< result.numberReturned:
    let doclen = s.peekInt32LE
    result.documents[i] = s.readStr(doclen).decode
    if s.atEnd or s.peekChar.byte == 0: break

proc prepareQuery*(s: Stream, reqId, target, opcode, flags: int32,
    collname: string, nskip, nreturn: int32,
    query = newbson(), selector = newbson()): int =
  result = s.msgHeader(reqId, target, opcode)

  s.writeLE flags;                     result += 4
  s.write collname; s.write 0x00.byte; result += collname.len + 1
  s.writeLE nskip; s.writeLE nreturn;  result += 2 * 4

  result += s.serialize query
  if not selector.isNil:
    result += s.serialize selector

  s.setPosition 0
  s.writeLE result.int32
  s.setPosition 0

template prepare*(q: BsonDocument, dbname: string): untyped =
  var s = newStringStream()
  discard s.prepareQuery(0, 0, opQuery.int32, 0, dbname, 0, 0, q)
  s

template check*(r: ReplyFormat): (bool, string) =
  var res = (false, "")
  if r.numberReturned <= 0 and r.responseFlags != opReply.int32:
    res[1] = "some error happened, cannot get, get response flag " &
      $r.responseFlags
  else:
    res = (true, "")
  res

proc queryOp(s: Stream, query = newbson(), selector = newbson()): int =
  s.prepareQuery(0, 0, opQuery.int32, 0, "temptest.role",
    0, 0, query, selector)

proc insertOp(s: Stream, data: BsonDocument): int =
  result = s.msgHeader(0, 0, opInsert.int32)
  s.write 0'i32
  result += 4
  let temptestdb = "temptest.role"
  s.write temptestdb
  s.write 0x00.byte
  result += temptestdb.len + 1
  dump data
  result += s.serialize data
  s.setPosition 0
  s.writeLE result.int32
  s.setPosition 0

proc acknowledgedInsert(s: Stream, data: BsonDocument,
    collname = "temptest.$cmd"): int =
  let insertQuery = bson({
    insert: "role",
    documents: [data]
  })
  result = s.prepareQuery(0, 0, opQuery.int32, 0,
    collname, 0, 1, insertQuery)


proc look*(reply: ReplyFormat) =
  dump reply.numberReturned
  if reply.numberReturned > 0 and
     "cursor" in reply.documents[0] and
     "firstBatch" in reply.documents[0]["cursor"].get.ofEmbedded:
    when not defined(release):
      echo "printing cursor"
    for d in reply.documents[0]["cursor"].get["firstBatch"].ofArray:
      dump d
  else:
    for d in reply.documents:
      dump d
    
proc ok*(b: BsonDocument): bool =
  "ok" in b and b["ok"].get.ofDouble.int == 1

proc errMsg*(b: BsonDocument): string =
  if "errMsg" in b:
    result = b["errMsg"].get

proc code*(b: BsonDocument): int =
  if "code" in b:
    result = b["code"].get

proc getReply*(socket: AsyncSocket): Future[ReplyFormat] {.discardable, async.} =
  var bstrhead = newStringStream(await socket.recv(size = 16))
  let msghdr = msgHeaderFetch bstrhead
  when not defined(release) or not defined(danger):
    dump msghdr
  let bytelen = msghdr.messageLength

  let rest = await socket.recv(size = bytelen-16)
  var restStream = newStringStream rest
  result = replyParse restStream

proc findAll(socket: AsyncSocket, selector = newbson()) {.async, used.} =
  var stream = newStringStream()
  discard stream.queryOp(newbson(), selector)
  await socket.send stream.readAll
  look(await socket.getReply)

proc insert(socket: AsyncSocket, doc: BsonDocument) {.async, used.} =
  var s = newStringStream()
  let _ = s.insertOp doc
  let data = s.readAll
  await socket.send data

proc insertAcknowledged(socket: AsyncSocket, doc: BsonDocument) {.async, used.} =
  var s = newStringStream()
  let _ = s.acknowledgedInsert doc
  let data = s.readAll
  await socket.send data
  look(await socket.getReply)

proc insertAckNewColl(socket: AsyncSocket, doc: BsonDocument) {.async, used.} =
  var s = newStringStream()
  discard s.acknowledgedInsert(doc, collname = "newcoll.$cmd")
  await socket.send s.readAll
  look( await socket.getReply )

let insertDoc {.used.} = bson({
  id: 3.toBson,
  role_name: "tester"
})

proc deleteAck(s: Stream, query: BsonDocument, n = 0): int =
  let q = bson({q: query, limit: n})
  let deleteEntry = bson({
    delete: "role",
    deletes: [q]
  })
  dump deleteEntry
  s.prepareQuery(0, 0, opQuery.int32, 0, "temptest.$cmd",
    0, 1, deleteEntry)

proc deleteAck(socket: AsyncSocket, query: BsonDocument, n = 0) {.async, used.} =
  var s = newStringStream()
  let _ = s.deleteAck(query, n)
  let data = s.readAll
  await socket.send data
  look( await socket.getReply )

proc updateAck(s: Stream, query, update: BsonDocument, multi = true,
    collname = "temptest.$cmd"): int =
  let updateEntry = bson({q: query, u: update, multi: multi})
  let updates = bson({update: "role", updates: [updateEntry]})
  dump updateEntry
  s.prepareQuery(0, 0, opQuery.int32, 0, collname,
    0, 1, updates)


proc updateAck(socket: AsyncSocket, query, update: BsonDocument,
    multi = true) {.async, used.} =
  var s = newStringStream()
  let _ = s.updateAck(query, update, multi)
  await socket.send s.readAll
  look( await socket.getReply )


proc queryAck*(sock: AsyncSocket, id: int32, dbname, collname: string,
  query = newbson(), selector = newbson(),
  sort = newbson(), skip = 0, limit = 0): Future[ReplyFormat] {.async.} =
  var s = newStringStream()
  let findq = bson({
    find: collname,
    filter: query,
    sort: sort,
    projection: selector,
    skip: skip,
    limit: limit
  })
  when not defined(release):
    dump findq
  discard s.prepareQuery(id, 0, opQuery.int32, 0, dbname & ".$cmd",
    skip.int32, 1, findq)
  await sock.send s.readAll
  result = await sock.getReply

proc getMore*(s: AsyncSocket, id: int64, dbname, collname: string,
  batchSize = 50, maxTimeMS = 0): Future[ReplyFormat] {.async.} =
  var ss = newStringStream()
  let moreq = bson({
    getMore: id,
    collection: collname,
    batchSize: batchSize,
    maxTimeMS: maxTimeMS,
  })
  when not defined(release):
    dump moreq
  discard ss.prepareQuery(0, 0, opQuery.int32, 0, dbname & ".$cmd",
    0, 1, moreq)
  await s.send ss.readAll
  result = await s.getReply

# not tested when there's no way to create database
proc dropDatabase*(sock: AsyncSocket, dbname = "temptest",
    writeConcern = newbson()): Future[ReplyFormat] {.async.} =
  var q = newbson(("dropDatabase", 1.toBson))
  if not writeConcern.isNil:
    q["writeConcern"] = writeConcern
  var s = newStringStream()
  discard s.prepareQuery(0, 0, opQuery.int32, 0, dbname & ".$cmd",
    0, 1, q)
  await sock.send s.readAll
  result = await sock.getReply

when isMainModule:
  var socket = newAsyncSocket()
  wait_for socket.connect("localhost", Port 27017)

  #socket.insert insertDoc

  #[
  socket.insertAcknowledged newbson(
    ("id", 5.toBson),
    ("role_name", "ack_insert".toBson)
  )
  ]#

  echo "\n======================"
  echo "original entries"
  wait_for socket.findAll
  let id4 = bson({
    id: 4,
    role_name: "new_insert"
  })

  echo "\n======================"
  echo "inserting id4 doc: ", id4
  wait_for socket.insertAcknowledged id4
  wait_for socket.findAll

  echo "\n======================"
  echo "updating id4 doc: "
  wait_for socket.updateAck(
    query = bson({"id": 4}),
    update = bson({ "$set": { role_name : "ephemeral_insert" }})
  )

  echo "\n======================"
  echo "finding out after update"
  waitFor socket.findAll

  echo "\n======================"
  echo "now deleting it"
  waitFor socket.deleteAck bson({"id": 4})

  echo "\n======================"
  echo "after deleting"
  waitFor socket.findAll

  let selector = bson({ role_name: 1 })
  echo "\n======================"
  echo "find with selector of ", selector
  waitFor socket.findAll selector

  echo "\n======================"
  echo "find with acknowledged query"
  dump waitFor socket.queryAck(0'i32, "temptest", "role", sort = bson({id: -1}))


  #[
  echo "\n======================"
  echo "insert new coll query"
  waitFor socket.insertAckNewColl newbson(("id", 4.toBson),
    ("role_name", "new".toBson))
  ]#
  close socket
