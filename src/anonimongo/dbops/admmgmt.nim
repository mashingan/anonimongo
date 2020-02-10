import strformat
import ../core/[types, bson, wire, utils, pool]

proc create*(db: Database, name: string, capsizemax = (false, 0, 0),
  storageEngine = bsonNull(),
  validator = bsonNull(), validationLevel = "strict", validationAction = "error",
  indexOptionDefaults = bsonNull(), viewOn = "",
  pipeline = bsonArray(), collation = bsonNull(), writeConcern = bsonNull()):
  Future[(bool, string)] {.async.} =
  var q = bson({
    create: name,
  })
  if capsizemax[0]:
    q["capped"] = true
    q["size"] = capsizemax[1]
    q["max"] = capsizemax[2]
  q.addOptional("storageEngine", storageEngine)
  q.addOptional("validator", validator)
  q["validationLevel"] = validationLevel
  q["validationAction"] = validationAction
  q.addOptional("indexOptionDefaults", indexOptionDefaults)
  if viewOn != "":
    q["viewOn"] = viewOn
  if pipeline.ofArray.len != 0:
    q["pipeline"] = pipeline
  q.addOptional("collation", collation)
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

proc dropDatabase*(db: Database, wt = bsonNull()):
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

proc listCollections*(db: Database, dbname = "", filter = bsonNull()):
  Future[seq[BsonBase]] {.async.} =
  var q = bson({ listCollections: 1})
  if not filter.isNil:
    q["filter"] = filter
  let reply = await sendops(q, db, dbname)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    result = res["cursor"]["firstBatch"].ofArray

proc listCollectionNames*(db: Database, dbname = ""):
  Future[seq[string]] {.async.} =
  for b in await db.listCollections(dbname):
    result.add b["name"].get

proc listDatabases*(db: Mongo | Database): Future[seq[BsonBase]] {.async.} =
  let q = bson({ listDatabases: 1 })
  when db is Mongo:
    let dbm = db["admin"]
  else:
    let dbm = db
  let reply = await sendops(q, dbm, "admin")
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    when not defined(release):
      echo "All database size: ", res["totalSize"].get.ofDouble
    result = res["databases"].get
  else:
    echo res.errmsg

proc listDatabaseNames*(db: Mongo | Database): Future[seq[string]] {.async.} =
  for d in await listDatabases(db):
    result.add d["name"].get

proc listIndexes*(db: Database, coll: string):
  Future[seq[BsonBase]]{.async.} =
  let q = bson({ listIndexes: coll })
  let reply = await sendops(q, db)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    result = res["cursor"]["firstBatch"].get

proc renameCollection*(db: Database, `from`, to: string, wt = bsonNull()):
  Future[(bool, string)] {.async.} =
  let source = &"{db.name}.{`from`}"
  let dest = &"{db.name}.{to}"
  var q = bson({
    renameCollection: source,
    to: dest,
    dropTarget: false,
  })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, "admin")

proc shutdown*(db: Mongo | Database, force = false, timeout = 0):
    Future[(bool, string)] {.async.} =
  var q = bson({ shutdown: 1, force: force, timeoutSecs: timeout })
  when db is Mongo:
    let mdb = db["admin"]
  else:
    let mdb = db
  try:
    result = await mdb.proceed(q, "admin")
  except IOError:
    result = (true, getCurrentExceptionMsg())

when isMainModule:
  import ../tests/admmgmt_test