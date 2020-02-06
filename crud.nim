import tables
import bson, types, wire, utils
import admmgmt
import sugar

proc find*(db: Database, coll: string,query: BsonDocument,
  sort = bsonNull(), selector = bsonNull(), hint = bsonNull(),
  skip = 0, limit = 0, batchSize = 101, singleBatch = false, comment = "",
  maxTimeMS = 0, readConcern = bsonNull(),
  max = bsonNull(), min = bsonNull(), returnKey = false, showRecordId = false,
  tailable = false, awaitData = false, oplogReplay = false,
  noCursorTimeout = false, partial = false,
  collation = bsonNull()): Future[BsonDocument]{.async.} =
  var q = bson({ find: coll, filter: query })
  for field, val in {
    "sort": sort,
    "projection": selector,
    "hint": hint}.toTable:
    q.addOptional(field, val)
  q["skip"] = skip
  q["limit"] = limit
  q["batchSize"] = batchSize
  q.addConditional("singleBatch", singleBatch)
  if comment != "":
    q["comment"] = comment
  if maxTimeMS > 0: q["maxTimeMS"] = maxTimeMS
  for k,v in { "readConcern": readConcern,
    "max": max, "min": min }.toTable:
    q.addOptional(k, v)
  for k,v in {
    "returnKey": returnKey,
    "showRecordId": showRecordId,
    "tailable": tailable,
    "awaitData": awaitData,
    "oplogReplay": oplogReplay,
    "noCursorTimeout": noCursorTimeout,
    "allowPartialResults": partial
  }.toTable:
    q.addConditional(k, v)
  q.addOptional("collation", collation)
  dump q
  let reply = await sendops(q, db)
  let (success, reason) = check reply
  if not success:
    raise newException(MongoError, reason)
  result = reply.documents[0]

when isMainModule:
  import testutils, pool
  var mongo = testsetup()
  if mongo.authenticated:
    var db = mongo["temptest"]
    dump waitFor db.find("role", bson())
    var resfind = waitFor db.find("role", bson(), batchSize = 1, singleBatch = true)
    dump resfind
    resfind = waitFor db.find("role", bson(), batchSize = 1)
    dump resfind
    discard waitFor mongo.shutdown(timeout = 10)
    close mongo.pool