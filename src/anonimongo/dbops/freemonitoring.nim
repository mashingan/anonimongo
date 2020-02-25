import ../core/[bson, types, utils, wire]

proc getFreeMonitoringStatus*(db: Database): Future[BsonDocument] {.async.} =
  result = await db.crudops(bson({
    getFreeMonitoringStatus: 1
  }), "admin")

proc setFreeMonitoring*(db: Database, action = "enable"):
  Future[BsonDocument] {.async.} =
  let q = bson({
    setFreeMonitoring: 1,
    action: action,
  })
  result = await db.crudops(q, "admin")

proc enableFreeMonitoring*(db: Database): Future[BsonDocument] {.async.} =
  result = await db.setFreeMonitoring("enable")

proc disableFreeMonitoring*(db: Database): Future[BsonDocument] {.async.} =
  result = await db.setFreeMonitoring("disable")