import tables, sequtils, asyncdispatch
import ../core/[bson, types, wire, utils, multisock]
import diagnostic

## Query and Write Operation Commands
## **********************************
##
## This APIs can be referred `here`_. This module handling all main
## CRUD operations and all of these are returning BsonDocument to
## give a higher-level APIs to handle the document. 
##
## One caveat that's different from the `Mongo documentation`__ is
## each of these API has additional parameter ``explain`` string
## which default to "" (empty string), or ``explainVerbosity``
## in case ``explain`` already defined before.
## Any non empty ``explain`` value will regarded as Cached Query
## and will invoke the ``diagnostic.explain``.
## Available ``explain`` values are "allPlansExecution", "queryPlanner",
## and "executionStats".
##
## The usage of ``getLastError`` discouraged as it's backward compability
## with older Mongo version and unnecessary with Acknowledged Query
## as the error immediately returned when operation failed.
##
## All APIs are async.
##
## .. _here: https://docs.mongodb.com/manual/reference/command/nav-crud/
##
## __ here_

proc find*(db: Database[AsyncSocket], coll: string,query = bson(),
  sort = bsonNull(), selector = bsonNull(), hint = bsonNull(),
  skip = 0, limit = 0, batchSize = 101, singleBatch = false, comment = "",
  maxTimeMS = 0, readConcern = bsonNull(),
  max = bsonNull(), min = bsonNull(), returnKey = false, showRecordId = false,
  tailable = false, awaitData = false, oplogReplay = false,
  noCursorTimeout = false, partial = false,
  collation = bsonNull(), explain = ""): Future[BsonDocument]{.multisock.} =
  var q = bson({ find: coll, filter: query })
  for field, val in {
    "sort": sort,
    "projection": selector,
    "hint": hint}.toTable:
    var ff = field
    q.addOptional(move ff, val)
  q["skip"] = skip
  q["limit"] = limit
  q["batchSize"] = batchSize
  q.addConditional("singleBatch", singleBatch)
  if comment != "":
    q["comment"] = comment
  if maxTimeMS > 0: q["maxTimeMS"] = maxTimeMS
  for k,v in { "readConcern": readConcern,
    "max": max, "min": min }.toTable:
    var kk = k
    q.addOptional(move kk, v)
  for k,v in {
    "returnKey": returnKey,
    "showRecordId": showRecordId,
    "tailable": tailable,
    "awaitData": awaitData,
    "oplogReplay": oplogReplay,
    "noCursorTimeout": noCursorTimeout,
    "allowPartialResults": partial
  }.toTable:
    var kk = k
    q.addConditional(move kk, v)
  q.addOptional("collation", collation)
  if explain != "": result = await db.explain(q, explain)
  else: result = await crudops(db, q)

proc getMore*(db: Database[AsyncSocket], cursorId: int64, collname: string, batchSize: int,
  maxTimeMS = -1): Future[BsonDocument]{.multisock.} =
  var q = bson({
    getMore: cursorId,
    collection: collname,
    batchSize: batchSize,
   })
   # added guard to fix this https://jira.mongodb.org/browse/DOCS-13346
  if maxTimeMS >= 0 and db.db.isTailable:
    q["maxTimeMS"] = maxTimeMS
  result = await db.crudops(q)

proc insert*(db: Database[AsyncSocket], coll: string, documents: seq[BsonDocument],
  ordered = true, wt = bsonNull(), bypass = false, explain = ""):
  Future[BsonDocument] {.multisock.} =
  var q = bson({
    insert: coll,
    documents: documents.map(toBson),
    ordered: ordered,
  })
  q.addWriteConcern(db, wt)
  q.addConditional("bypassDocumentValidation", bypass)
  if explain != "": result = await db.explain(q, explain, command = ckWrite)
  else: result = await db.crudops(q, cmd = ckWrite)

proc delete*(db: Database[AsyncSocket], coll: string, deletes: seq[BsonDocument],
  ordered = true, wt = bsonNull(), explain = ""):
  Future[BsonDocument]{.multisock.} =
  var q = bson({
    delete: coll,
    deletes: deletes.map toBson,
    ordered: ordered,
  })
  q.addWriteConcern(db, wt)
  if explain != "": result = await db.explain(q, explain, command = ckWrite)
  else: result = await db.crudops(q, cmd = ckWrite)

proc update*(db: Database[AsyncSocket], coll: string, updates: seq[BsonDocument],
  ordered = true, wt = bsonNull(), bypass = false, explain = ""):
  Future[BsonDocument]{.multisock.} =
  var q = bson({
    update: coll,
    updates: updates.map toBson,
    ordered: ordered,
  })
  q.addWriteConcern(db, wt)
  q.addConditional("bypassDocumentValidation", bypass)
  if explain != "": result = await db.explain(q, explain, command = ckWrite)
  else: result = await db.crudops(q, cmd = ckWrite)

proc findAndModify*(db: Database[AsyncSocket], coll: string, query = bson(),
  sort = bsonNull(), remove = false, update = bsonNull(),
  `new` = false, fields = bsonNull(), upsert = false, bypass = false,
  wt = bsonNull(), collation = bsonNull(),
  arrayFilters: seq[BsonDocument] = @[], explain = ""): Future[BsonDocument]{.multisock.} =
  var q = bson({
    findAndModify: coll,
    query: query,
  })
  let bopts = [("sort", sort), ("update", update), ("fields", fields)]
  let conds = [("remove", remove), ("new", `new`), ("upsert", upsert)]
  for i in 0 .. conds.high:
    var b = bopts[i]
    q.addOptional(move b[0], b[1])
    var c = conds[i]
    q.addConditional(move c[0], c[1])
  q.addConditional("bypassDocumentValidation", bypass)
  q.addWriteConcern(db, wt)
  q.addOptional("collation", collation)
  if arrayFilters.len > 0:
    q["arrayFilters"] = arrayFilters.map toBson
  if explain != "": result = await db.explain(q, explain, command = ckWrite)
  else: result = await db.crudops(q, cmd = ckWrite)

proc getLastError*(db: Database[AsyncSocket], opt = bson()): Future[BsonDocument]{.multisock.} =
  var q = bson({ getLastError: 1 })
  for k, v in opt:
    var kk = k
    q[move kk] = v
  result = await db.crudops(q)