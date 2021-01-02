import streams, strformat
import asyncdispatch, asyncnet
from sugar import dump
import bson

import supersnappy, zippy

export streams, asyncnet, asyncdispatch

const verbose {.booldefine.} = false

type
  OpCode* = enum
    ## Wire protocol OP_CODE.
    opReply = 1'i32
    opUpdate = 2001'i32
    opInsert opReserved opQuery opGetMore opDelete opKillCursors
    opCommand = 2010'i32
    opCommandReply
    opCompressed
    opMsg = 2013'i32

  CompressorId* {.size: sizeof(uint8).} = enum
    ## Compression ID which will be used as indicattor what
    ## kind of compression used when sending the message.
    cidNoop = (0, "noop") # NOOP. The content is uncompressed.
    cidSnappy = "snappy" # Using snappy compression.
    cidZlib = "zlib" # using zlib compression.
    cidZstd = "zstd" # using zstd compression.

  MsgHeader* = object
    ## An object that will spearhead any exchanges of Bson data.
    messageLength*, requestId*, responseTo*, opCode*: int32

  ReplyFormat* = object
    ## Object that actually holds the values from Bson data.
    responseFlags*: int32
    cursorId*: int64
    startingFrom*: int32
    numberReturned*: int32
    documents*: seq[BsonDocument]

  Flags* {.size: sizeof(int32), pure.} = enum
    ## Bitfield used when query the mongo command.
    Reserved
    TailableCursor
    SlaveOk
    OplogReplay     ## mongodb internal use only, don't set
    NoCursorTimeout ## disable cursor timeout, default timeout 10 minutes
    AwaitData       ## used with tailable cursor
    Exhaust
    Partial         ## get partial data instead of error when some shards are down
  QueryFlags* = set[Flags]
    ## Flags itself that holds which bit flags available.

  RFlags* {.size: sizeof(int32), pure.} = enum
    ## RFlags is bitfield flag for ``ReplyFormat.responseFlags``
    CursorNotFound
    QueryFailure
    ShardConfigStale
    AwaitCapable
  ResponseFlags* = set[RFlags]
    ## The actual available ResponseFlags.

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
  ## Get the ReplyFormat from given data stream.
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
    query = newbson(), selector = newbson(), compression = cidNoop): int =
  ## Convert and encode the query into stream to be ready for sending
  ## onto TCP wire socket.
  template writeStream(msgstream: Stream): int =
    var length = 0
    msgstream.writeLE flags;                             length += 4
    msgstream.write collname; msgstream.write 0x00.byte; length += collname.len + 1
    msgstream.writeLE nskip; msgstream.writeLE nreturn;  length += 2 * 4

    length += msgstream.serialize query
    if not selector.isNil:
      length += msgstream.serialize selector
    length

  if compression == cidNoop:
    result = s.msgHeader(reqId, target, opcode)
    result += s.writeStream

  else:
    result = s.msgHeader(reqId, target, opCompressed.int32)
    var ss = newStringStream()
    let length = ss.writeStream
    s.writeLE opcode
    s.writeLE length.int32
    s.write compression.uint8
    ss.setPosition 0
    let msgall = ss.readAll
    result += 2 * sizeof(int32) + sizeof(byte)
    case compression
    of cidSnappy:
      let compressedMsg = supersnappy.compress(msgall)
      result += compressedMsg.len
      s.write compressedMsg
    of cidZlib:
      let compressedMsg = zippy.compress(msgall.bytes, dataformat = dfZlib)
      result += compressedMsg.len
      for b in compressedMsg: s.write b
    else:
      # not supported compression id
      let prev = s.getPosition
      s.setPosition prev-1
      s.write cidNoop
      result += msgall.len
      s.write msgall

  s.setPosition 0
  s.writeLE result.int32
  s.setPosition 0

template prepare*(q: BsonDocument, flags: int32, dbname: string,
  id = 0, skip = 0, limit = 1, compression = cidNoop): untyped =
  var s = newStringStream()
  discard s.prepareQuery(id, 0, opQuery.int32, flags, dbname, skip,
    limit, q, compression = compression)
  unown(s)

proc ok*(b: BsonDocument): bool =
  ## Check whether BsonDocument is ``ok``.
  result = false
  if "ok" in b:
    # Need this due to inconsistencies returned from Atlas Mongo
    if b["ok"].kind == bkInt32:
      result = b["ok"].ofInt32 == 1
    elif b["ok"].kind == bkDouble:
      result = b["ok"].ofDouble.int == 1

proc errmsg*(b: BsonDocument): string =
  ## Helper to fetch error message from BsonDocument.
  if "errmsg" in b:
    result = b["errmsg"]

proc code*(b: BsonDocument): int =
  ## Fetch (error?) code from BsonDocument.
  if "code" in b:
    result = b["code"]

template check*(r: ReplyFormat): (bool, string) =
  ## Utility that will check whether the ReplyFormat is successful
  ## failed and return it as tuple of bool and string.
  var res = (false, "")
  let rflags = r.responseFlags as ResponseFlags
  if r.numberReturned <= 0:
    res[1] = "some error happened, cannot get, get response flag " &
      $rflags
  elif r.numberReturned == 1:
    let doc = r.documents[0]
    if doc.ok:
      res[0] = true
    elif RFlags.QueryFailure in rflags and "$err" in doc:
      res[1] = doc["$err"]
    elif "errmsg" in doc:
      res[1] = doc["errmsg"]
  else:
    res[0] = true
  unown(res)

proc look*(reply: ReplyFormat) =
  ## Helper for easier debugging and checking the returned ReplyFormat.
  when verbose:
    dump reply.numberReturned
  if reply.numberReturned > 0 and
     "cursor" in reply.documents[0] and
     "firstBatch" in reply.documents[0]["cursor"].ofEmbedded:
    when not defined(release):
      echo "printing cursor"
    for d in reply.documents[0]["cursor"]["firstBatch"].ofArray:
      dump d
  else:
    for d in reply.documents:
      dump d
    
proc getReply*(socket: AsyncSocket): Future[ReplyFormat] {.async.} =
  ## Get data from socket and apply the replyParse into the result.
  var bstrhead = newStringStream(await socket.recv(size = 16))
  let msghdr = msgHeaderFetch bstrhead
  when verbose:
    dump msghdr
  let bytelen = msghdr.messageLength
  var rest = await socket.recv(size = bytelen-16)
  var restStream = newStringStream move(rest)
  if msghdr.opCode != opCompressed.int32:
    result = replyParse restStream
  else:
    discard restStream.readIntLE int32
    discard restStream.readIntLE int32
    let compression = restStream.readInt8.CompressorId
    case compression
    of cidSnappy:
      let origmsg = supersnappy.uncompress(restStream.readAll)
      result = replyParse newStringStream(origmsg)
    of cidZlib:
      let origmsg = zippy.uncompress(restStream.readAll.bytes).stringbytes
      result = replyParse newStringStream(origmsg)
    else:
      discard
  when verbose:
    look result

proc getMore*(s: AsyncSocket, id: int64, dbname, collname: string,
  batchSize = 50, maxTimeMS = 0): Future[ReplyFormat] {.async.} =
  ## Retrieve more data from cursor id. The returned documents
  ## are in result["cursor"]["nextBatch"] instead of in firstBatch.
  var ss = newStringStream()
  let moreq = bson({
    getMore: id,
    collection: collname,
    batchSize: batchSize,
    maxTimeMS: maxTimeMS,
  })
  when verbose:
    dump moreq
  discard ss.prepareQuery(0, 0, opQuery.int32, 0, dbname & ".$cmd",
    0, 1, moreq)
  await s.send ss.readAll
  result = await s.getReply

# not tested when there's no way to create database
proc dropDatabase*(sock: AsyncSocket, dbname = "temptest",
    writeConcern = newbson()): Future[ReplyFormat] {.async.} =
  ## Artifact from older APIs development. Don't use it.
  var q = newbson(("dropDatabase", 1.toBson))
  if not writeConcern.isNil:
    q["writeConcern"] = writeConcern
  var s = newStringStream()
  discard s.prepareQuery(0, 0, opQuery.int32, 0, dbname & ".$cmd",
    0, 1, q)
  await sock.send s.readAll
  result = await sock.getReply