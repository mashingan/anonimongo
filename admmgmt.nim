import strformat
import types, bson, wire, utils, pool

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
  #let filter = bson({ name: 1 })
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
  #result = await mdb.proceed(q, "admin")
  var s = prepare(q, mdb.flags, "admin".cmd)
  let (id, conn) = await mdb.db.pool.getConn()
  defer: mdb.db.pool.endConn id
  await conn.socket.send s.readAll
  if not conn.socket.isClosed:
    try:
      result = check await conn.socket.getReply
    except:
      result =(true, getCurrentExceptionMsg())
  else:
    result = (true, "")

when isMainModule:
  import sugar
  import testutils
  var mongo = testsetup()
  if mongo.authenticated:
    for db in waitFor mongo.listDatabases:
      dump db
    var db = mongo["admin"]
    let targetColl = "testtemptest"
    let newtgcoll = "newtemptest"
    # test create collection
    db.name = "temptest"
    var (success, reason) = waitFor db.create(targetColl)
    if not success:
      echo "Cannot create collection: ", reason
    else:
      echo "successfully create collection", targetColl

    for c in waitFor db.listCollections(filter = bson({
      idIndex: 1, info: 1, options: 1
    })):
      dump c

    (success, reason) = waitFor db.renameCollection(targetColl, newtgcoll)
    if not success:
      echo &"Cannot rename collection from {targetColl} to {newtgcoll}: {reason}"
    else:
      echo &"successfully rename from {targetColl} to {newtgcoll}"

    for name in waitFor db.listCollectionNames:
      dump name

    (success, reason) = waitFor db.dropCollection(newtgcoll)
    if not success:
      echo &"Cannot drop collection {newtgcoll}: {reason}"
    else:
      echo &"Collection {newtgcoll} dropped"

    for currname in waitFor db.listCollectionNames:
      dump currname

    (success, reason) = waitFor mongo.shutdown(timeout = 10)
    dump success
    dump reason

    close mongo.pool