import strformat
import ../core/[types, bson, wire, utils]
import multisock

proc isMaster*(db: Database[AsyncSocket], cmd = bson()): Future[BsonDocument]{.multisock.} =
  var q = bson({
    isMaster: 1,
  })
  let sasl = "saslSupportedMechs"
  if sasl in cmd:
    q[sasl] = cmd[sasl]
  if "any" in cmd:
    q["any"] = cmd["any"]
  result = await db.crudops(q)

proc replSetAbortPrimaryCatchUp*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({replSetAbortPrimaryCatchUp: 1}), cmd = ckWrite)

proc replSetFreeze*(db: Database[AsyncSocket], seconds: int): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({replSetFreeze: seconds}), cmd = ckWrite)

proc replSetGetConfig*(db: Database[AsyncSocket], commitmentStatus: bool, comment = bsonNull()):
  Future[BsonDocument]{.multisock.} =
  var q = bson({
    replSetGetConfig: 1,
    commitmentStatus: commitmentStatus,
  })
  if not comment.isNil:
    q["comment"] = comment
  result = await db.crudops(q)

proc replSetGetStatus*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  var q = bson({
    replSetGetStatus: 1,
  })
  result = await db.crudops(q, "admin")

proc replSetInitiate*(db: Database[AsyncSocket], config: BsonDocument):
  Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({
    replSetInitiate: config
  }))

proc replSetMaintenance*(db: Database[AsyncSocket], enable: bool):
  Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ replSetMaintenance: enable}), "admin", cmd = ckWrite)

proc replSetReconfig*(db: Database[AsyncSocket], newconfig: BsonDocument, force: bool,
  maxTimeMS: int = -1): Future[BsonDocument]{.multisock.} =
  var q = bson({
    replSetReconfig: newconfig,
    force: force,
  })
  if maxTimeMS != -1:
    q["maxTimeMS"] = maxTimeMS
  result = await db.crudops(q, "admin", cmd = ckWrite)

proc replSetResizeOplog*(db: Database[AsyncSocket]; size: float; minRetentionHours = 0.0):
  Future[BsonDocument]{.multisock.} =
  var q = bson({
    replSetResizeOplog: 1,
    size: size,
    minRetentionHours: minRetentionHours
  })
  result = await db.crudops(q, "admin", cmd = ckWrite)

proc replSetStepDown*(db: Database[AsyncSocket], stepDown: int, catchup = 10, force  = false):
  Future[BsonDocument]{.multisock.} =
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
  result = await db.crudops(q, "admin", cmd = ckWrite)

proc replSetSyncFrom*(db: Database[AsyncSocket], hostport: string): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({replSetSyncFrom: hostport}), cmd = ckWrite)