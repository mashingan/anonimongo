import ../core/[bson, types, utils, wire, multisock]

proc getFreeMonitoringStatus*(db: Database[AsyncSocket]): Future[BsonDocument] {.multisock.} =
  result = await db.crudops(bson({
    getFreeMonitoringStatus: 1
  }), "admin")

proc setFreeMonitoring*(db: Database[AsyncSocket], action = "enable"):
  Future[BsonDocument] {.multisock.} =
  let q = bson({
    setFreeMonitoring: 1,
    action: action,
  })
  result = await db.crudops(q, "admin", cmd = ckWrite)

proc enableFreeMonitoring*(db: Database[AsyncSocket]): Future[BsonDocument] {.multisock.} =
  result = await db.setFreeMonitoring("enable")

proc disableFreeMonitoring*(db: Database[AsyncSocket]): Future[BsonDocument] {.multisock.} =
  result = await db.setFreeMonitoring("disable")