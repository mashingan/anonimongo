import sequtils
import ../core/[bson, types, utils, wire, multisock]

## Diagnostics Commands
## ********************
##
## This APIs can be referred `here`_. All these APIs are returning BsonDocument
## so check the `Mongo documentation`__.
##
## **Beware**: These APIs are not tested.
##
## All APIs are async.
##
## .. _here: https://docs.mongodb.com/manual/reference/command/nav-diagnostic/
## __ here_

proc buildInfo*(db: Database[AsyncSocket]): Future[BsonDocument] {.multisock.} =
  result = await db.crudops(bson({ buildInfo: 1 }))

proc collStats*(db: Database[AsyncSocket], coll: string, scale = 1024):
  Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ collStats: coll, scale: scale}))

proc connPoolStats*(db: Database[AsyncSocket]): Future[BsonDocument] {.multisock.} =
  result = await db.crudops(bson({ connPoolStats: 1 }))

proc connectionStatus*(db: Database[AsyncSocket], showPriv = false): Future[BsonDocument] {.multisock.} =
  result = await db.crudops(bson({
    connectionStatus: 1, showPrivileges: showPriv
  }))

proc dataSize*(db: Database[AsyncSocket], coll: string, pattern = bson({"_id": 1}),
  min = bson(), max = bson(), estimate = false): Future[BsonDocument]{.multisock.} =
  var q = bson({ dataSize: coll, keyPattern: pattern })
  q.addOptional("min", min)
  q.addOptional("max", max)
  q.addConditional("estimate", estimate)
  result = await db.crudops(q)

proc dbHash*(db: Database[AsyncSocket], colls: seq[string] = @[]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({
    dbHash: 1, collections: colls.map toBson
  }))

proc dbStats*(db: Database[AsyncSocket], scale = 1024): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({
    dbStats: 1, scale: scale
  }))

proc explain*(db: Database[AsyncSocket], cmd = bson(), verbosity = "allPlansExecution", command = ckRead):
  Future[BsonDocument] {.multisock.} =
  let q = bson({ explain: cmd, verbosity: verbosity })
  result = await db.crudops(q, cmd = command)

proc getCmdLineOpts*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ getCmdLineOpts: 1 }), "admin")

proc getLog*(db: Database[AsyncSocket], filter = "global"): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ getLog: filter }), "admin")

proc getLogFilters*(db: Database[AsyncSocket]): Future[seq[string]] {.multisock.} =
  let names = await db.getLog("*")
  result = names["names"].ofArray.map ofString

proc hostInfo*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ hostInfo: 1 }), "admin")

proc listCommands*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ listCommands: 1 }))

proc ping*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ ping: 1 }))

proc profile*(db: Database[AsyncSocket], level = 0, slowms = 100, sampleRate = 1.0):
  Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({
    profile: level,
    slowms: slowms,
    sampleRate: sampleRate
  }))

proc serverStat*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({serverStatus:1}))

proc shardConnPoolStats*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ shardConnPoolStats: 1 }))

proc top*(db: Database[AsyncSocket]): Future[BsonDocument]{.multisock.} =
  result = await db.crudops(bson({ top: 1 }), "admin")

proc validate*(db: Database[AsyncSocket], coll: string, full = false):
  Future[BsonDocument] {.multisock.} =
  var q = bson({ validate: coll })
  q.addOptional("full", full)
  result = await db.crudops(q)