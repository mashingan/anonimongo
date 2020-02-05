import types, bson, wire, utils

proc create*(db: Database, name: string, capsizemax = (false, 0, 0),
  storageEngine = bsonNull(),
  validator = bsonNull(), validationLevel = "strict", validationAction = "error",
  indexOptionDefaults = bsonNull(), viewOn = "",
  pipeline = bsonArray(), collation = bsonNull(), writeConcern = bsonNull()):
  Future[(bool, string)] {.async.} =
  var q = bson({
    create: name,
    capped: capsizemax[0],
    size: capsizemax[1],
    max: capsizemax[2],
    storageEngine: storageEngine,
    validator: validator,
    validationLevel: validationLevel,
    validationAction: validationAction,
    viewOn: viewOn,
    pipeline: pipeline,
    collation: collation,
  })
  q.addWriteConcern(db, writeConcern)
  result = await db.proceed(q)

proc createIndexes*(db: Database, coll: string, indexes: BsonArray,
  writeConcern = bsonNull()): Future[(bool, string)]{.async.} =
  var q = bson({
    createIndexes: coll,
    indexes: indexes,
  })
  q.addWriteConcern(db, writeConcern)
  result = await db.proceed(q)

proc dropCollection*(db: Database, coll: string, wt = bsonNull()):
  Future[(bool, string)]{.async.} =
  var q = bson({ drop: coll })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc dropDatabase*(db: Database, coll: string, wt = bsonNull()):
  Future[(bool, string)]{.async.} =
  var q = bson({ dropDatabase: 1 })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc dropIndexes*(db: Database, coll: string, indexes: BsonBase,
  wt = bsonNull()): Future[(bool, string)] {.async.} =
  var q = bson({
    dropIndexes: coll,
    indexes: indexes,
  })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc listCollections*(db: Database, dname = "", filter = bsonNull()):
  Future[seq[string]] {.async.} =
  var q = bson({ listCollections: 1})
  if not filter.isNil:
    q["filter"] = filter
  let reply = await sendops(q, db, dname)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    let arr = res["cursor"]["firstBatch"].ofArray
    result = newseq[string](arr.len)
    for i, d in arr:
      # assume it's ok
      result[i] = d["name"].get