import tables, sequtils
import ../core/[bson, types, wire, utils]

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
  q["maxTimeMS"] = maxTimeMS
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
  limit = 0, skip = 0, hint = bsonNull(), readConcern = bsonNull(),
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

proc mapReduce*(db: Database, coll: string, map, reduce: BsonJs,
  `out`: BsonBase, query = bson(), sort = bsonNull(), limit = 0,
  finalize = bsonNull(), scope = bsonNull(), jsMode = false, verbose = false,
  bypass = false, collation = bsonNull(), wt = bsonNull()):
  Future[BsonDocument]{.async.} =
  var q = bson({
    mapReduce: coll,
    map: map,
    reduce: reduce,
    `out`: `out`,
    query: query
  })
  q.addOptional("sort", sort)
  if limit > 0: q["limit"] = limit
  for k, v in {
    "finalize": finalize,
    "scope": scope
  }.toTable:
    q.addOptional(k, v)
  for k, v in {
    "jsMode": jsMode,
    "verbose": verbose,
    "bypassDocumentValidation": bypass
  }.toTable:
    q.addConditional(k, v)
  q.addOptional("collation", collation)
  q.addWriteConcern(db, q)
  result = await db.crudops(q)

proc geoSearch*(db: Database, coll: string, search: BsonDocument,
  near: seq[BsonDocument], maxDistance = 0, limit = 0,
  readConcern = bsonNull()): Future[BsonDocument]{.async.} =
  var q = bson({
    geoSearch: coll,
    search: search,
    near: near.map toBson,
  })
  if maxDistance > 0: q["maxDistance"] = maxDistance
  if limit > 0: q["limit"] = limit
  q.addOptional("readConcern", readConcern)
  result = await db.crudops(q)