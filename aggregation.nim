import sequtils
import bson, types, wire, utils

proc aggregate*(db: Database, coll: string, pipeline: seq[BsonDocument],
  explain = false, diskuse = false, cursor = bson(), maxTimeMS = 0,
  bypass = false, readConcern = bsonNull(), collation = bsonNull(),
  hint = bsonNull(), comment = "", wt = bsonNull()): Future[BsonDocument]{.async.} =
  var q = bson({
    aggregate: coll,
    pipeline: pipeline.map toBson,
  })
  for kv in [("explain", explain), ("allowDiskUse", diskuse)]:
    q.addConditional(kv[0], kv[1])
  if not explain:
    q["cursor"] = cursor
  q["maxTImeMS"] = maxTimeMS
  q.addConditional("bypassDocumentValidation", bypass)
  for kv in [
    ("readConcern", readConcern),
    ("collation", collation),
    ("hint", hint)
  ]:
    q.addOptional(kv[0], kv[1])
  if comment != "": q["comment"] = comment
  q.addWriteConcern(db, wt)
  result = await db.crudops(q)

proc count*(db: Database, coll: string, query = bson(),
  limit = 1, skip = 0, hint = bsonNull(), readConcern = bsonNull(),
  collation = bsonNull()): Future[BsonDocument] {.async.} =
  var q = bson({
    count: coll,
    query: query,
    limit: limit,
    skip: skip,
  })
  for kv in [
    ("hint", hint),
    ("readConcern", readConcern),
    ("collation", collation)
  ]:
    q.addOptional(kv[0], kv[1])
  result = await db.crudops(q)

proc `distinct`*(db: Database, coll, key: string, query = bson(),
  readConcern = bsonNull(), collation = bsonNull()):
  Future[BsonDocument]{.async.} =
  var q = bson({
    `distinct`: coll,
    key: key,
    query: query,
  })
  for kv in [
    ("readConcern", readConcern),
    ("collation", collation)
  ]:
    q.addOptional(kv[0], kv[1])
  result = await db.crudops(q)