import sequtils
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
  result = doc["cursor"]["firstBatch"][0]

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
  opt = bson()): Future[(bool, int)] {.async.} =
  var q = bson({
    q: query,
    u: updates,
   })
  for k, v in opt:
   q[k] = v
  let doc = await c.db.update(c.name, @[q])
  result = (doc.ok, doc["nModified"].ofInt)

proc remove*(c: Collection, query: BsonDocument, justone = false):
    Future[(bool, int)] {.async.} =
  let limit = if justone: 1 else: 0
  var delq = bson({
    q: query,
    limit: limit
  })
  let doc = await c.db.delete(c.name, @[delq])
  result = (doc.ok, doc["n"].ofInt)

proc remove*(c: Collection, query, opt: BsonDocument):
  Future[(bool, int)] {.async.} =
  var delq = bson({ query: query })
  var wt: BsonBase
  for k, v in opt:
    if k == "writeConcern": wt = v
    else: delq[k] = v
  let doc = await c.db.delete(c.name, @[delq], wt = wt)
  result = (doc.ok, doc["n"].ofInt)

proc insert*(c: Collection, docs: seq[BsonDocument], opt = bson()):
  Future[(bool, int)] {.async.} =
  let wt = if "writeConcern" in opt: opt["writeConcern"] else: bsonNull()
  let ordered = if "ordered" in opt: opt["ordered"].ofBool else: true
  let doc = await c.db.insert(c.name, docs, ordered, wt)
  result = (doc.ok, doc["n"].ofInt)

proc drop*(c: Collection, wt = bsonNull()): Future[(bool, string)] {.async.} =
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
  Future[(bool, string)] {.async.} =
  let wt = if "writeConcern" in opt: opt["writeConcern"]
           else: bsonNull()
  var q = bson({ key: key })
  for k, v in opt:
    q[k] = v
  let qarr = bsonArray q.toBson
  result = await c.db.createIndexes(c.name, qarr, wt)

proc `distinct`*(c: Collection, field: string, query = bson(),
  opt = bson()): Future[seq[BsonBase]] {.async.} =
  var readConcern, collation: BsonBase
  if "readConcern" in opt: readConcern = opt["readConcern"]
  if "collation" in opt: collation = opt["collation"]
  let doc = await c.db.`distinct`(c.name, field, query, readConcern, collation)
  result = doc["values"].ofArray

proc dropIndex*(c: Collection, indexes: BsonBase):
  Future[(bool, string)] {.async.} =
  result = await c.db.dropIndexes(c.name, indexes)

proc dropIndexes*(c: Collection, indexes: seq[string]):
  Future[(bool, string)] {.async.} =
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