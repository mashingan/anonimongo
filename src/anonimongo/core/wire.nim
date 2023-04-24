import streams, strformat, strutils
import asyncdispatch, asyncnet, net
from sugar import dump
import bson
import streamable
import multisock

import supersnappy, zippy

export streams, asyncnet, asyncdispatch

const anoverbose {.booldefine.} = false

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

  MsgBitFlags* {.size: sizeof(int32), pure.} = enum
    ## The OP_MESSAGE bit flag definition
    ChecksumPresent
    MoreToCome
    ExhaustAllowed = 16
  MsgFlags* = set[MsgBitFlags]
    ## The actual bitfield value for message flags.

const msgDefaultFlags = 0

proc serialize(s: var Streamable, doc: BsonDocument): int =
  let (doclen, docstr) = encode doc
  result = doclen
  s.write docstr

proc msgHeader(s: var Streamable, reqId, returnTo, opCode: int32): int=
  result = 16
  s.write 0'i32
  s.writeLE reqId
  s.writeLE returnTo
  s.writeLE opCode

proc msgHeaderFetch(s: var Streamable): MsgHeader =
  MsgHeader(
    messageLength: s.readIntLE int32,
    requestId: s.readIntLE int32,
    responseTo: s.readIntLE int32,
    opCode: s.readIntLE int32
  )

proc replyParse*(s: var Streamable): ReplyFormat =
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

proc msgParse*(s: var Streamable, rest = 0): ReplyFormat =
  ## Get the message in the ReplyFormat from given data stream.
  ## This is adapted to older type ReplyFormat from newer wire
  ## protocol OP_MSG.
  result = ReplyFormat(
    numberReturned: 1,
  )
  var restlen = rest
  let respflags {.used.} = (s.readIntLE int32) as MsgBitFlags
  restlen -= sizeof int32
  when anoverbose:
    dump respflags
  let sectionkind {.used.} = s.readUint8
  restlen -= sizeof byte
  when anoverbose:
    dump sectionkind
  let doclen = s.peekInt32LE
  restlen -= doclen
  result.documents = @[s.readStr(doclen).decode]

proc prepareQuery*(s: var Streamable, reqId, target, opcode, flags: int32,
    collname: string, nskip, nreturn: int32,
    query = newbson(), selector = newbson(), compression = cidNoop): int =
  ## Convert and encode the query into stream to be ready for sending
  ## onto TCP wire socket.
  var query = query
  query["$db"] = collname.split(".")[0]

  when anoverbose:
    dump query

  template writeStream(ss: Stream): int =
    ss.writeLE msgDefaultFlags.int32
    ss.write 0.byte # kind 0: body
    var length = ss.serialize(query) + sizeof(byte) + sizeof(int32)
    length

  if compression == cidNoop:
    let opcode = opMsg.int32
    result = s.msgHeader(reqId, target, opcode)
    result += s.writeStream

  else:
    result = s.msgHeader(reqId, target, opCompressed.int32)
    var ss = newStringStream()
    let length = ss.writeStream
    let opcode = opMsg.int32
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
  ## or failed and return it as tuple of bool and string.
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
  when anoverbose:
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
    
proc getReply*(socket: AsyncSocket): Future[ReplyFormat] {.multisock.} =
  ## Get data from socket and apply the replyParse into the result.
  var bstrhead = newStringStream(await socket.recv(size = 16))
  let msghdr = msgHeaderFetch bstrhead
  when anoverbose:
    dump msghdr
  let bytelen = msghdr.messageLength
  var rest = await socket.recv(size = bytelen-16)
  var restStream = newStringStream move(rest)
  if msghdr.opCode == opReply.int32:
    result = replyParse restStream
  elif msghdr.opCode == opMsg.int32:
    result = msgParse(restStream, bytelen-16)
  else:
    let oriopcode = restStream.readIntLE int32
    let orirest = restStream.readIntLE int32
    var origmsg: string
    let compression = restStream.readInt8.CompressorId
    case compression
    of cidSnappy:
      origmsg = supersnappy.uncompress(restStream.readAll)
    of cidZlib:
      origmsg = zippy.uncompress(restStream.readAll.bytes).stringbytes
    else:
      return # do nothing
    var msg = newStream origmsg
    if oriopcode == opReply.int32:
      result = replyParse msg
    elif oriopcode == opMsg.int32:
      result = msgParse(msg, orirest)
  when anoverbose:
    look result
