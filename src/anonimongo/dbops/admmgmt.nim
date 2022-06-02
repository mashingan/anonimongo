import std/[strformat, sequtils]
from std/sugar import `=>`
import ../core/[types, bson, wire, utils, multisock]

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

proc create*(db: Database[AsyncSocket], name: string, capsizemax = (false, 0, 0),
  storageEngine = bsonNull(),
  validator = bsonNull(), validationLevel = "strict", validationAction = "error",
  indexOptionDefaults = bsonNull(), viewOn = "",
  pipeline = bsonArray(), collation = bsonNull(), writeConcern = bsonNull(),
  expireAfterSeconds = 0, timeseries = bsonNull()):
  Future[WriteResult] {.multisock.} =
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

proc createIndexes*(db: Database[AsyncSocket], coll: string, indexes: BsonBase,
  writeConcern = bsonNull(), commitQuorum = bsonNull(), comment = bsonNull()):
  Future[WriteResult]{.multisock.} =
  var q = bson({
    createIndexes: coll,
    indexes: indexes,
  })
  q.addWriteConcern(db, writeConcern)
  q.addOptional("commitQuorum", commitQuorum)
  q.addOptional("comment", comment)
  result = await db.proceed(q, cmd = ckWrite)

proc dropCollection*(db: Database[AsyncSocket], coll: string, wt = bsonNull(),
  comment = bsonNull()): Future[WriteResult]{.multisock.} =
  var q = bson({ drop: coll })
  q.addWriteConcern(db, wt)
  q.addOptional("comment", comment)
  result = await db.proceed(q, cmd = ckWrite)

proc dropDatabase*(db: Database[AsyncSocket], wt = bsonNull(), comment = bsonNull()):
  Future[WriteResult]{.multisock.} =
  var q = bson({ dropDatabase: 1 })
  q.addWriteConcern(db, wt)
  q.addOptional("comment", comment)
  result = await db.proceed(q, cmd = ckWrite)

proc dropIndexes*(db: Database[AsyncSocket], coll: string, indexes: BsonBase,
  wt = bsonNull(), comment = bsonNull()): Future[WriteResult] {.multisock.} =
  var q = bson({
    dropIndexes: coll,
    index: indexes,
  })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, cmd = ckWrite)

proc listCollections*(db: Database[AsyncSocket], dbname = "", filter = bsonNull(),
  nameonly = false, authorizedCollections = false, comment = bsonNull()):
  Future[seq[BsonBase]] {.multisock.} =
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

proc listCollectionNames*(db: Database[AsyncSocket], dbname = ""):
  Future[seq[string]] {.multisock.} =
  for b in await db.listCollections(dbname):
    var name: string = b["name"]
    result.add name.move

# proc listDatabases*(db: Mongo | Database, filter = bsonNull(), nameonly = false,
proc listDatabases*(db: Database[AsyncSocket], filter = bsonNull(), nameonly = false,
  authorizedCollections = false, comment = bsonNull()): Future[seq[BsonBase]] {.multisock.} =
  var q = bson({ listDatabases: 1 })
  q.addOptional("filter", filter)
  q.addConditional("nameOnly", nameonly)
  q.addConditional("authorizedCollections", authorizedCollections)
  q.addOptional("comment", comment)
  # when db is Mongo:
  #   let dbm = db["admin"]
  # else:
  #   let dbm = db
  let dbm = db
  let reply = await sendops(q, dbm, "admin", cmd = ckRead)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let res = reply.documents[0]
  if res.ok:
    when not defined(release): echo "All database size: ", res["totalSize"]
    result = res["databases"]
  else:
    echo res.errmsg

# proc listDatabaseNames*(db: Mongo | Database): Future[seq[string]] {.multisock.} =
proc listDatabaseNames*(db: Database[AsyncSocket]): Future[seq[string]] {.multisock.} =
  for d in await listDatabases(db):
    result.add d["name"]

proc listIndexes*(db: Database[AsyncSocket], coll: string, comment = bsonNull()):
  Future[seq[BsonBase]]{.multisock.} =
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

proc renameCollection*(db: Database[AsyncSocket], `from`, to: string, wt = bsonNull(),
  comment = bsonNull()):
  Future[WriteResult] {.multisock.} =
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

# proc shutdown*(db: Mongo | Database, force = false, timeout = 10,
proc shutdown*(db: Database[AsyncSocket], force = false, timeout = 10,
  comment = bsonNull()): Future[WriteResult] {.multisock.} =
  var q = bson({ shutdown: 1, force: force, timeoutSecs: timeout })
  q.addOptional("comment", comment)
  let mdb = db
  try:
    result = await mdb.proceed(q, "admin", cmd = ckWrite)
  except IOError:
    result = WriteResult(
      success: true,
      reason: getCurrentExceptionMsg(),
      kind: wkSingle
    )

proc shutdown*(m: Mongo[AsyncSocket], force = false, timeout = 10,
  comment = bsonNull()): Future[WriteResult] {.multisock.} =
  let db = m["admin"]
  result = await db.shutdown(force, timeout, comment)

proc currentOp*(db: Database[AsyncSocket], opt = bson()): Future[BsonDocument]{.multisock.} =
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

proc killOp*(db: Database[AsyncSocket], opid: int32, comment = bsonNull()):
  Future[WriteResult] {.multisock.} =
  var q = bson({ killerOp: 1, op: opid })
  q.addConditional("comment", comment)
  result = await db.proceed(q, "admin", cmd = ckWrite)

# template sendEpilogue(db: Database[AsyncSocket], q: BsonDocument, mode: CommandKind): untyped =
proc sendEpilogue(db: Database[AsyncSocket], q: BsonDocument, mode: CommandKind): Future[BsonDocument] {.multisock.} =
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendops(q, db, "admin", cmd = mode, compression = compression)
  let (success, reason) = check reply
  if not success:
    echo reason
    result = bsonNull()
    return
  result = reply.documents[0]

proc killCursors*(db: Database[AsyncSocket], collname: string, cursorIds: seq[int64]):
  Future[BsonDocument] {.multisock.} =
  let q = bson({ killCursors: collname, cursors: cursorIds.map toBson })
  result = await sendEpilogue(db, q, ckWrite)

proc setDefaultRWConcern*(db: Database[AsyncSocket], defaultReadConcern = bsonNull(),
  defaultWriteConcern = bsonNull(), wt = bsonNull(), comment = bsonNull()):
  Future[BsonDocument]{.multisock.} =
  if all([defaultReadConcern, defaultWriteConcern].map(isNil), (x) => x ):
    result = bsonNull()
    return
  var q = bson { setDefaultRWConcern: 1 }
  q.addOptional("defaultReadConcern", defaultReadConcern)
  q.addOptional("defaultWriteConcern", defaultWriteConcern)
  q.addOptional("writeConcern", wt)
  q.addOptional("comment", comment)
  result = await sendEpilogue(db, q, ckWrite)

proc getDefaultReadConcern*(db: Database[AsyncSocket], inMemory = false, comment = bsonNull()):
  Future[BsonDocument]{.multisock.} =
  let q = bson { getDefaultReadConcern: 1,  inMemory: inMemory, comment: comment}
  result = await sendEpilogue(db, q, ckRead)