import tables, sequtils
import ../core/[bson, types, wire, utils]
import diagnostic

## Aggregation commands (and a Geospatial command)
## ***********************************************
##
## Ref to `Mongo command`_ documentation for better understanding of each API
## and its return value is BsonDocument. Geospatial command can be found `here`_.
##
## All APIs are async.
##
## .. _Mongo command: https://docs.mongodb.com/manual/reference/command/nav-aggregation/
## .. _here: https://docs.mongodb.com/manual/reference/command/geoSearch/#dbcmd.geoSearch

proc aggregate*(db: Database, coll: string, pipeline: seq[BsonDocument],
  explain = false, diskuse = false, cursor = bson(), maxTimeMS = 0,
  bypass = false, readConcern = bsonNull(), collation = bsonNull(),
  hint = bsonNull(), comment = "", wt = bsonNull(), explainVerbosity = ""):
  Future[BsonDocument]{.async.} =
  var q = bson({
    aggregate: coll,
    pipeline: pipeline.map toBson,
  })
  for kv in [("explain", explain), ("allowDiskUse", diskuse)]:
    var kv0 = kv[0]
    q.addConditional(move kv0, kv[1])
  if not explain:
    q["cursor"] = cursor
  q["maxTimeMS"] = maxTimeMS
  q.addConditional("bypassDocumentValidation", bypass)
  for kv in [
    ("readConcern", readConcern),
    ("collation", collation),
    ("hint", hint)
  ]:
    var kv0 = kv[0]
    q.addOptional(move kv0, kv[1])
  if comment != "": q["comment"] = comment
  q.addWriteConcern(db, wt)
  if explainVerbosity != "": result = await db.explain(q, explainVerbosity)
  else: result = await db.crudops(q)

proc count*(db: Database, coll: string, query = bson(),
  limit = 0, skip = 0, hint = bsonNull(), readConcern = bsonNull(),
  collation = bsonNull(), explain = ""): Future[BsonDocument] {.async.} =
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
    var kv0 = kv[0]
    q.addOptional(move kv0, kv[1])
  if explain != "": result = await db.explain(q, explain)
  else: result = await db.crudops(q)

proc `distinct`*(db: Database, coll, key: string, query = bson(),
  readConcern = bsonNull(), collation = bsonNull(), explain = ""):
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
    var kv0 = kv[0]
    q.addOptional(move kv0, kv[1])
  if explain != "": result = await db.explain(q, explain)
  else: result = await db.crudops(q)

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
