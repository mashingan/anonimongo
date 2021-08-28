import std/[strformat, sequtils]
from std/sugar import `=>`
import ../core/[types, bson, wire, utils]

## Administration Commands
## ***********************
##
## The actual APIs documentation can be referred to `Mongo command`_
## documentation for better understanding of each API and its return
## value or BsonDocument. Any read commands will return either
## ``seq[BsonBase]`` or ``seq[BsonDocument]`` for fine tune handling
## query result.
##
## For any write/update/modify/delete commands, it will usually return
## tuple of bool success and string reason or bool of success and int
## n of affected documents.
##
## All APIs are async.
##
## .. _Mongo command: https://docs.mongodb.com/manual/reference/command/nav-administration/

proc create*(db: Database, name: string, capsizemax = (false, 0, 0),
  storageEngine = bsonNull(),
  validator = bsonNull(), validationLevel = "strict", validationAction = "error",
  indexOptionDefaults = bsonNull(), viewOn = "",
  pipeline = bsonArray(), collation = bsonNull(), writeConcern = bsonNull(),
  expireAfterSeconds = 0, timeseries = bsonNull()):
  Future[WriteResult] {.async.} =
  var q = bson({
    create: name,
  })
  if capsizemax[0]:
    q["capped"] = true
    q["size"] = capsizemax[1]
    q["max"] = capsizemax[2]
  q.addOptional("timeseries", timeseries)
  if expireAfterSeconds > 0: q["expireAfterSeconds"] = expireAfterSeconds
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
  result = await db.proceed(q, cmd = ckWrite)

proc createIndexes*(db: Database, coll: string, indexes: BsonBase,
  writeConcern = bsonNull(), commitQuorum = bsonNull(), comment = bsonNull()):
  Future[WriteResult]{.async.} =
  var q = bson({
    createIndexes: coll,
    indexes: indexes,
  })
  q.addWriteConcern(db, writeConcern)
  q.addOptional("commitQuorum", commitQuorum)
  q.addOptional("comment", comment)
  result = await db.proceed(q, cmd = ckWrite)

proc dropCollection*(db: Database, coll: string, wt = bsonNull(),
  comment = bsonNull()): Future[WriteResult]{.async.} =
  var q = bson({ drop: coll })
  q.addWriteConcern(db, wt)
  q.addOptional("comment", comment)
  result = await db.proceed(q, cmd = ckWrite)

proc dropDatabase*(db: Database, wt = bsonNull(), comment = bsonNull()):
  Future[WriteResult]{.async.} =
  var q = bson({ dropDatabase: 1 })
  q.addWriteConcern(db, wt)
  q.addOptional("comment", comment)
  result = await db.proceed(q, cmd = ckWrite)

proc dropIndexes*(db: Database, coll: string, indexes: BsonBase,
  wt = bsonNull(), comment = bsonNull()): Future[WriteResult] {.async.} =
  var q = bson({
    dropIndexes: coll,
    index: indexes,
  })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, cmd = ckWrite)

proc listCollections*(db: Database, dbname = "", filter = bsonNull(),
  nameonly = false, authorizedCollections = false, comment = bsonNull()):
  Future[seq[BsonBase]] {.async.} =
  var q = bson({ listCollections: 1})
  if not filter.isNil:
    q["filter"] = filter
  q.addConditional("nameOnly", nameonly)
  q.addConditional("authorizedCollections", authorizedCollections)
  q.addOptional("comment", comment)
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendops(q, db, dbname, cmd = ckRead, compression = compression)
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
    var name: string = b["name"]
    result.add name.move

proc listDatabases*(db: Mongo | Database, filter = bsonNull(), nameonly = false,
  authorizedCollections = false, comment = bsonNull()): Future[seq[BsonBase]] {.async.} =
  let q = bson({ listDatabases: 1 })
  q.addOptional("filter", filter)
  q.addConditional("nameOnly", nameonly)
  q.addConditional("authorizedCollections", authorizedCollections)
  q.addOptional("comment", comment)
  when db is Mongo:
    let dbm = db["admin"]
  else:
    let dbm = db
  let reply = await sendops(q, dbm, "admin", cmd = ckRead)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    when not defined(release):
      # why this? in mongo 4.0 the size is double
      # but during the build in github action, the type
      # is changed to int hence this guard
      stdout.write "All database size: "
      let total = res["totalSize"]
      if total.kind == bkDouble:
        echo total.ofDouble
      elif total.kind in [bkInt32,bkInt64]:
        echo total.ofInt
      # echo "All database size: ", res["totalSize"].ofInt
    result = res["databases"]
  else:
    echo res.errmsg

proc listDatabaseNames*(db: Mongo | Database): Future[seq[string]] {.async.} =
  for d in await listDatabases(db):
    result.add d["name"]

proc listIndexes*(db: Database, coll: string, comment = bsonNull()):
  Future[seq[BsonBase]]{.async.} =
  var q = bson({ listIndexes: coll })
  q.addOptional("comment", comment)
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendops(q, db, cmd = ckRead, compression = compression)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    result = res["cursor"]["firstBatch"]

proc renameCollection*(db: Database, `from`, to: string, wt = bsonNull(),
  comment = bsonNull()):
  Future[WriteResult] {.async.} =
  let source = &"{db.name}.{`from`}"
  let dest = &"{db.name}.{to}"
  var q = bson({
    renameCollection: source,
    to: dest,
    dropTarget: false,
  })
  q.addWriteConcern(db, wt)
  q.addOptional("comment", comment)
  result = await db.proceed(q, "admin", cmd = ckWrite)

proc shutdown*(db: Mongo | Database, force = false, timeout = 10,
  comment = bsonNull()): Future[WriteResult] {.async.} =
  var q = bson({ shutdown: 1, force: force, timeoutSecs: timeout })
  q.addOptional("comment", comment)
  when db is Mongo:
    let mdb = db["admin"]
  else:
    let mdb = db
  try:
    result = await mdb.proceed(q, "admin", cmd = ckWrite)
  except IOError:
    result = WriteResult(
      success: true,
      reason: getCurrentExceptionMsg(),
      kind: wkSingle
    )

proc currentOp*(db: Database, opt = bson()): Future[BsonDocument]{.async.} =
  var q = bson({ currentOp: 1})
  for k, v in opt:
    q[k] = v
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendops(q, db, "admin", cmd = ckRead, compression = compression)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  result = reply.documents[0]

proc killOp*(db: Database, opid: int32, comment = bsonNull()):
  Future[WriteResult] {.async.} =
  var q = bson({ killerOp: 1, op: opid })
  q.addConditional("comment", comment)
  result = await db.proceed(q, "admin", cmd = ckWrite)

proc killCursors*(db: Database, collname: string, cursorIds: seq[int64]):
  Future[BsonDocument] {.async.} =
  let q = bson({ killCursors: collname, cursors: cursorIds.map toBson })
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendops(q, db, cmd = ckWrite, compression = compression)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  result = reply.documents[0]

proc setDefaultRWConcern*(db: Database, defaultReadConcern = bsonNull(),
  defaultWriteConcern = bsonNull(), wt = bsonNull(), comment = bsonNull()):
  Future[BsonDocument]{.async.} =
  if all([defaultReadConcern, defaultWriteConcern].map(isNil), (x) => x ):
    result = bsonNull()
    return
  var q = bson { setDefaultRWConcern: 1'i32 }
  q.addOptional("defaultReadConcern", defaultReadConcern)
  q.addOptional("defaultWriteConcern", defaultWriteConcern)
  q.addOptional("writeConcern", wt)
  q.addOptional("comment", comment)
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendOps(q, db, "admin", cmd = ckWrite,
    compression = compression)
  let (success, reason) = check reply
  if not success:
    echo reason
    result = bsonNull()
    return
  result = reply.documents[0]