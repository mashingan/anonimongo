import oids
from sequtils import concat, map, mapIt

import anonimongo/core/[bson, types, wire]
import anonimongo/dbops/[aggregation, crud]

import multisock

const csVerbose = defined(changeStreamVerbose)

when csVerbose:
  import sugar

type
  ChangeStreamEvent* = enum
    csInsert = "insert"
    csUpdate = "update"
    csReplace = "replace"
    csDelete = "delete"
    csInvalidate = "invalidate"
    csDrop = "drop"
    csDropDatabase = "dropDatabase"
    csRename = "rename"
  ChangeStreamId* = object
    data* {.bsonKey: "_data".}: string
  Namespace* = object
    db*: string
    coll*: string
  DocumentKey* = object
    id* {.bsonKey: "_id".}: Oid
  ChangeStream* = object
    id* {.bsonKey: "_id".}: ChangeStreamId
    operationType*: ChangeStreamEvent
    fullDocument*: BsonDocument
    ns*: Namespace
    documentKey*: DocumentKey

proc forEach*(c: Cursor[AsyncSocket], cb: proc(b: ChangeStream),
  stopWhen: set[ChangeStreamEvent]): Future[void] {.multisock.} =
  let db = c.db
  var c = c
  let collname = c.collname
  #defer: asyncCheck db.killCursors(collname, @[c.id])
  var cs: ChangeStream
  template processEntry(el, label: untyped) =
    cs = `el`.to ChangeStream
    cb(cs)
    when csVerbose: dump cs
    if cs.operationType in stopWhen:
      break `label`
  block always:
    while c.id != 0:
      when csVerbose: dump db == nil
      if db == nil: break always
      for fbatch in c.firstBatch: processEntry fbatch, always
      for nbatch in c.nextBatch: processEntry nbatch, always
      var forEachReply: BsonDocument
      try:
        forEachReply = await db.getMore(c.id, collname, 101)
      except CatchableError:
        echo getCurrentExceptionMsg()
        break always

      #discard sleepAsync 1_000
      when csVerbose: dump forEachReply
      if not forEachReply.ok:
        break always
      c = forEachReply["cursor"].ofEmbedded.toCursor[:AsyncSocket]

proc watch*(coll: Collection[AsyncSocket], pipelines: seq[BsonDocument] = @[],
  options = bson()): Future[Cursor[AsyncSocket]] {.multisock.} =
  var queries = newseq[BsonDocument](pipelines.len+1)
  queries[0] = bson { "$changeStream": options }
  queries = concat(queries, pipelines)
  when csVerbose: dump queries
  let reply = await coll.db.aggregate(coll.name, queries, maxTimeMS = 0)
  if not reply.ok:
    raise newException(MongoError, getCurrentExceptionMsg())
  result = reply["cursor"].ofEmbedded.toCursor[:AsyncSocket]
  result.db = coll.db
  when csVerbose: dump result