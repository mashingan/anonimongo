import sequtils
import ../core/core

proc buildInfo*(db: Database): Future[BsonDocument] {.async.} =
  result = await db.crudops(bson({ buildInfo: 1 }))

proc collStats*(db: Database, coll: string, scale = 1024):
  Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ collStats: coll, scale: scale}))

proc connPoolStats*(db: Database): Future[BsonDocument] {.async.} =
  result = await db.crudops(bson({ connPoolStats: 1 }))

proc connectionStatus*(db: Database, showPriv = false): Future[BsonDocument] {.async.} =
  result = await db.crudops(bson({
    connectionStatus: 1, showPrivileges: showPriv
  }))

proc dataSize*(db: Database, coll: string, pattern = bson({"_id": 1}),
  min = bson(), max = bson(), estimate = false): Future[BsonDocument]{.async.} =
  var q = bson({ dataSize: coll, keyPattern: pattern })
  q.addOptional("min", min)
  q.addOptional("max", max)
  q.addConditional("estimate", estimate)
  result = await db.crudops(q)

proc dbHash*(db: Database, colls: seq[string] = @[]): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({
    dbHash: 1, collections: colls.map toBson
  }))

proc dbStats*(db: Database, scale = 1024): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({
    dbStats: 1, scale: scale
  }))

proc explain*(db: Database, cmd = bson(), verbosity = "allPlansExecution"):
  Future[BsonDocument] {.async.} =
  let q = bson({ explain: cmd, verbosity: verbosity })
  result = await db.crudops(q)

proc getCmdLineOpts*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ getCmdLineOpts: 1 }), "admin")

proc getLog*(db: Database, filter = "global"): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ getLog: filter }), "admin")

proc getLogFilters*(db: Database): Future[seq[string]] {.async.} =
  result = (await db.getLog("*"))["names"].get.ofArray.map ofString

proc hostInfo*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ hostInfo: 1 }), "admin")

proc listCommands*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ listCommands: 1 }))

proc ping*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ ping: 1 }))

proc profile*(db: Database, level = 0, slowms = 100, sampleRate = 1.0):
  Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({
    profile: level,
    slowms: slowms,
    sampleRate: sampleRate
  }))

proc serverStat*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({serverStatus:1}))

proc shardConnPoolStats*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ shardConnPoolStats: 1 }))

proc top*(db: Database): Future[BsonDocument]{.async.} =
  result = await db.crudops(bson({ top: 1 }), "admin")

proc validate*(db: Database, coll: string, full = false):
  Future[BsonDocument] {.async.} =
  var q = bson({ validate: coll })
  q.addOptional("full", full)
  result = await db.crudops(q)