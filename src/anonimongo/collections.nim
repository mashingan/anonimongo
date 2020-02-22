import sequtils, strformat
import sugar

import dbops/[admmgmt, aggregation, aggregation, crud]
import core/[bson, types, utils, wire]

{.warning[UnusedImport]: off.}

## Collection Methods
## ******************
##
## Collection module implements selected APIs documented `here`_ in Mongo page.
## Not all APIs will be implemented as there are several APIs that just
## helper based on more basic APIs. This methods offload the actual operations
## to `dbops crud`_ module hence any resemblance on the parameter with a bit
## differents in returned values. The APIs methods implemented here can be
## viewed as higher-level than `dbops crud`_ module APIs.
##
## Collection should return `Query`_ / `Cursor`_ type or anything that will run
## for the actual query. Users can set the values for queries setting
## before actual query request.
##
## .. _here: https://docs.mongodb.com/manual/reference/method/js-collection/
## .. _dbops crud: dbops/crud.html
## .. _Query: core/types.html#Query
## .. _Cursor: core/types.html#Cursor

## The strategies here will consist of:
##
## 1. Collection invoke methods
## 2. Got the query necessary
## 3. Users chose how to run the query e.g.
##
##      a. Find a document about it
##      b. Find several documents about it
##      c. Iterate the documents for it
##

## Query will return Cursor that implement `items`_ iterators to iterate whether
## firstBatch field or nextBatch field and will immediately `getMore`_ if it's empty.
##
## .. _items: #items.i,Cursor
## .. _getMore: dbops/crud.html#getMore,Database,int64,string,int

proc one*(q: Query): Future[BsonDocument] {.async.} =
  let doc = await q.collection.db.find(q.collection.name, q.query, q.sort,
    q.projection, skip = q.skip, limit = 1, singleBatch = true)
  let batch = doc["cursor"]["firstBatch"].ofArray
  if batch.len > 0:
    result = batch[0]
  else:
    result = bson()

proc all*(q: Query): Future[seq[BsonDocument]] {.async.} =
  var doc = await q.collection.db.find(q.collection.name, q.query, q.sort,
    q.projection, skip = q.skip, limit = q.limit)
  var cursor = doc["cursor"].ofEmbedded.to Cursor
  result = cursor.firstBatch
  if result.len >= q.limit:
    return
  while cursor.id > 0:
    doc = await q.collection.db.getMore(cursor.id, q.collection.name,
      batchSize = q.batchSize)
    cursor = doc["cursor"].ofEmbedded.to Cursor
    if cursor.nextBatch.len == 0:
      break
    result = concat(result, cursor.nextBatch)

iterator items*(cur: Cursor): BsonDocument =
  for b in cur.firstBatch:
    yield b
  let batchSize = if cur.firstBatch.len != 0: cur.firstBatch.len
                  else: 101
  var doc: BsonDocument
  var newcur = cur
  let collname = newcur.collname
  while newcur.id != 0:
    #doc = await cur.db.getMore(cur.id, collname, batchSize)
    doc = waitfor newcur.db.getMore(newcur.id, collname, batchSize)
    newcur = doc["cursor"].ofEmbedded.to Cursor
    newcur.db = cur.db
    if newcur.nextBatch.len <= 0:
      break
    for b in newcur.nextBatch:
      yield b

proc iter*(q: Query): Future[Cursor] {.async.} =
  var doc = await q.collection.db.find(q.collection.name, q.query, q.sort,
    q.projection, skip = q.skip, limit = q.limit)
  result = doc["cursor"].ofEmbedded.to Cursor
  result.db = q.collection.db

proc find*(c: Collection, query = bson(), projection = bsonNull()): Query =
  result = initQuery(query, c)
  result.projection = projection

proc findOne*(c: Collection, query = bson(), projection = bsonNull(),
  sort = bsonNull()): Future[BsonDocument] {.async.} =
  var q = c.find(query, projection)
  q.sort = sort
  result = await q.one

proc findAll*(c: Collection, query = bson(), projection = bsonNull(),
  sort = bsonNull()): Future[seq[BsonDocument]] {.async.} =
  var q = c.find(query, projection)
  q.sort = sort
  result = await q.all

proc findIter*(c: Collection, query = bson(), projection = bsonNull(),
  sort = bsonNull()): Future[Cursor] {.async.} =
  var q = c.find(query, projection)
  q.sort = sort
  result = await q.iter

proc findAndModify*(c: Collection, query = bson(), sort = bsonNull(),
  remove = false, update = bsonNull(), `new` = false, fields = bsonNull(),
  upsert = false, bypass = false, wt = bsonNull(), collation = bsonNull(),
  arrayFilters: seq[BsonDocument] = @[]): Future[BsonDocument]{.async.} =
  let doc = await c.db.findAndModify(c.name, query, sort, remove, update, `new`,
    fields, upsert, bypass, wt, collation, arrayFilters)
  result = doc["value"].ofEmbedded

proc update*(c: Collection, query = bson(), updates = bsonNull(),
  opt = bson()): Future[WriteResult] {.async.} =
  var q = bson({
    q: query,
    u: updates,
   })
  var ordered = true
  for k, v in opt:
    if k == "ordered": ordered = v.ofBool
    else: q[k] = v
  let doc = await c.db.update(c.name, @[q], ordered = ordered)
  result = doc.getWResult

proc remove*(c: Collection, query: BsonDocument, justone = false):
    Future[WriteResult] {.async.} =
  let limit = if justone: 1 else: 0
  var delq = bson({
    q: query,
    limit: limit
  })
  let doc = await c.db.delete(c.name, @[delq])
  result = doc.getWResult

proc remove*(c: Collection, query, opt: BsonDocument):
  Future[WriteResult] {.async.} =
  var delq = bson({ query: query })
  var wt: BsonBase
  for k, v in opt:
    if k == "writeConcern": wt = v
    else: delq[k] = v
  let doc = await c.db.delete(c.name, @[delq], wt = wt)
  result = doc.getWResult

proc insert*(c: Collection, docs: seq[BsonDocument], opt = bson()):
  Future[WriteResult] {.async.} =
  let wt = if "writeConcern" in opt: opt["writeConcern"] else: bsonNull()
  let ordered = if "ordered" in opt: opt["ordered"].ofBool else: true
  let doc = await c.db.insert(c.name, docs, ordered, wt)
  result = doc.getWResult

proc drop*(c: Collection, wt = bsonNull()): Future[WriteResult] {.async.} =
  result = await c.db.dropCollection(c.name, wt)

proc count*(c: Collection, query = bson(), opt = bson()):
  Future[int] {.async.} =
  var
    hint, readConcern, collation: BsonBase
    limit = 0
    skip = 0
  for k, v in opt:
    case k
    of "hint": hint = v
    of "readConcern": readConcern = v
    of "collation": collation = v
    of "limit": limit = v
    of "skip": skip = v
  let doc = await c.db.count(c.name, query, limit, skip, hint,
    readConcern, collation)
  result = doc["n"]

proc createIndex*(c: Collection, key: BsonDocument, opt = bson()):
  Future[WriteResult] {.async.} =
  let wt = if "writeConcern" in opt: opt["writeConcern"]
           else: bsonNull()
  var q = bson({ key: key })
  if "name" notin opt:
    var name = ""
    for k, v in key:
      name &= &"{k}_{v}_"
    q["name"] = name
  for k, v in opt:
    q[k] = v
  let qarr = bsonArray q.toBson
  result = await c.db.createIndexes(c.name, qarr, wt)

proc listIndexes*(c: Collection): Future[seq[BsonDocument]]{.async.} =
  result = (await c.db.listIndexes(c.name)).map ofEmbedded

proc `distinct`*(c: Collection, field: string, query = bson(),
  opt = bson()): Future[seq[BsonBase]] {.async.} =
  var readConcern, collation: BsonBase
  if "readConcern" in opt: readConcern = opt["readConcern"]
  if "collation" in opt: collation = opt["collation"]
  let doc = await c.db.`distinct`(c.name, field, query, readConcern, collation)
  result = doc["values"].ofArray

proc dropIndex*(c: Collection, indexes: BsonBase):
  Future[WriteResult] {.async.} =
  result = await c.db.dropIndexes(c.name, indexes)

proc dropIndexes*(c: Collection, indexes: seq[string]):
  Future[WriteResult] {.async.} =
  result = await c.db.dropIndexes(c.name, indexes.map toBson)

proc aggregate*(c: Collection, pipeline: seq[BsonDocument], opt = bson()):
  Future[seq[BsonDocument]]{.async.} =
  type tempopt = object
    explain, diskuse: bool
    cursor: BsonDocument
    maxTimeMS: int
    bypass: bool
    readConcern, collation, hint: BsonBase
    comment: string
    wt: BsonBase
  var optobj = opt.to tempopt
  if not optobj.explain and optobj.cursor.isNil:
    optobj.cursor = bson()
  let reply = await c.db.aggregate(c.name, pipeline,
    optobj.explain, optobj.diskuse, optobj.cursor, optobj.maxTimeMS,
    optobj.bypass, optobj.readConcern, optobj.collation, optobj.hint,
    optobj.comment, optobj.wt)
  result = reply["cursor"]["firstBatch"].ofArray.map ofEmbedded

proc preparebulkUpdate(op: BsonDocument, wt: BsonBase, ordered: bool,
  db: Database): (BsonDocument, BsonBase, BsonDocument) =
  result[1] = bsonNull()
  result[2] = bson()
  for k, v in op:
    if k == "filter": result[0] = v.ofEmbedded
    elif k == "update": result[1] = v
    else: result[2][k] = v
  if not ordered:
    result[2]["ordered"] = false
  result[2].addWriteConcern(db, wt)

proc bulkWrite*(c: Collection, operations: seq[BsonDocument],
  wt = bsonNull(), ordered = true): Future[BulkResult] {.async.} =
  var wr: WriteResult
  let opt = bson({ writeConcern: wt, ordered: ordered })
  var futbulk = newseq[Future[WriteResult]](operations.len)
  var opid = newseq[string](operations.len)
  template checkOrdered(wr: WriteResult, target, fieldName: untyped): untyped =
    if not wr.success or wr.errmsgs.len != 0:
      if wr.reason != "":
        `target`.writeErrors.add wr.reason
      for s in wr.errmsgs:
        `target`.writeErrors.add s
      if ordered: return
    `target`.`fieldName` += wr.n
  template opcheck(optype: string, fut: Future[WriteResult], i: int,
    field: untyped): untyped =
    if not ordered:
      futbulk[i] = fut
      opid[i] = optype
    else:
      wr = await fut
      checkOrdered(wr, result, field)
  template updateOp(optype: string, op: BsonDocument, i: int): untyped =
    let (query, update, updopt) = op[optype].ofEmbedded.
      preparebulkUpdate(wt, ordered, c.db)
    let futupd = c.update(query, update, updopt)
    opcheck(optype, futupd, i, nModified)
  template removeOp(optype: string, op: BsonDocument, i: int, one = false):
    untyped =
    let fut = c.remove(op[optype]["filter"].ofEmbedded, justone = one)
    opcheck(optype, fut, i, nRemoved)
  for i, op in operations:
    if "insertOne" in op:
      let futInsOne = c.insert(@[op["insertOne"]["document"].ofEmbedded], opt)
      opcheck("insertOne", futInsOne, i, nInserted)
    elif "deleteOne" in op:
      removeOp("deleteOne", op, i, true)
    elif "updateOne" in op:
      updateOp("updateOne", op, i)
    elif "deleteMany" in op:
      removeOp("deleteMany", op, i)
    elif "updateMany" in op:
      updateOp("updateMany", op, i)
    elif "replaceOne" in op:
      var (query, _, updopt) = op["replaceOne"].ofEmbedded.
        preparebulkUpdate(wt, ordered, c.db)
      updopt.del "replacement"
      let update = op["replaceOne"]["replacement"]
      let futrepOne = c.update(query, update, updopt)
      opcheck("replaceOne", futrepOne, i, nModified)
    else:
      var key: string
      for k, _ in op:
        key = k
        break
      raise newException(MongoError, &"Invalid command given: {key}")
  if not ordered:
    let futres = await all(futbulk)
    for i in 0 .. futres.high:
      if opid[i] == "insertOne":
        checkOrdered(futres[i], result, nInserted)
      elif opid[i] in ["updateOne", "updateMany", "replaceOne"]:
        checkOrdered(futres[i], result, nModified)
      elif opid[i] in ["deleteOne", "deleteMany"]:
        checkOrdered(futres[i], result, nRemoved)