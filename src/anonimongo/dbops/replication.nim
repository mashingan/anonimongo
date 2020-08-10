import strformat
import ../core/[types, bson, wire, utils]

proc isMaster*(db: Database, cmd = bson()): Future[BsonDocument]{.async.} =
  var q = bson({
    isMaster: 1,
  })
  let sasl = "saslSupportedMechs"
  if sasl in cmd:
    q[sasl] = cmd[sasl]
  if "any" in cmd:
    q["any"] = cmd["any"]
  result = await db.crudops(q)

proc replSetAbortPrimaryCatchUp*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({replSetAbortPrimaryCatchUp: 1}))

proc replSetFreeze*(db: Database, seconds: int): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({replSetFreeze: seconds}))

proc replSetGetConfig*(db: Database, commitmentStatus: bool, comment = bsonNull()):
  Future[BsonDocument]{.async.} =
  var q = bson({
    replSetGetConfig: 1,
    commitmentStatus: commitmentStatus,
  })
  if not comment.isNil:
    q["comment"] = comment
  result = await db.crudops(q)

proc replSetGetStatus*(db: Database): Future[BsonDocument]{.async.} =
  var q = bson({
    replSetGetStatus: 1,
  })
  result = await db.crudops(q, "admin")

proc replSetInitiate*(db: Database, config: BsonDocument):
  Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({
    replSetInitiate: config
  }))

proc replSetMaintenance*(db: Database, enable: bool):
  Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ replSetMaintenance: enable}), "admin")

proc replSetReconfig*(db: Database, newconfig: BsonDocument, force: bool,
  maxTimeMS: int): Future[BsonDocument]{.async.} =
  var q = bson({
    replSetReconfig: newconfig,
    force: force,
    maxTimeMS: maxTimeMS
  })
  result = await db.crudops(q, "admin")

proc replSetResizeOplog*(db: Database; size: float; minRetentionHours = 0.0):
  Future[BsonDocument]{.async.} =
  var q = bson({
    replSetResizeOplog: 1,
    size: size,
    minRetentionHours: minRetentionHours
  })
  result = await db.crudops(q, "admin")

proc replSetStepDown*(db: Database, stepDown: int, catchup = 10, force  = false):
  Future[BsonDocument]{.async.} =
  var q = bson({
    replSetStepDown: stepDown
  })
  var catchup = catchup
  if force: catchup = 0
  if stepDown < catchup:
    raise newException(MongoError,
      &"stepDown ({stepDown}s) cannot less than catchup ({catchup}s)")
  q["secondaryCatchUpPeriodSecs"] = catchup
  q["force"] = force
  result = await db.crudops(q, "admin")

proc replSetSyncFrom*(db: Database, hostport: string): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({replSetSyncFrom: hostport}))