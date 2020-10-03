const testChangeStreams {.booldefine.} = false

when testChangeStreams:
  import unittest, threadpool, times, os, osproc, strformat
  import utils_test, utils_replica
  import anonimongo


  proc cleanResources(p: seq[Process]) =
    cleanup p
    sleep 1_000
    cleanMongoTemp()
    cleanupSSL()

  proc setReplica(m: Mongo): bool =
    var config = bson({
      "_id": rsetName,
      members: [
        { "_id": 0, host: &"{mongoServer}:{replicaPortStart}", priority: 2 },
        { "_id": 1, host: &"{mongoServer}:{replicaPortStart+1}" },
        { "_id": 2, host: &"{mongoServer}:{replicaPortStart+2}" },
      ]
    })
    var reply: BsonDocument
    var db = m["admin"]
    try:
      reply = waitfor db.replSetInitiate(config)
    except MongoError:
      echo getCurrentExceptionMsg()
      return false
    result = reply.ok
    close m

  proc inserting(c: Collection, cursorId: int64) {.async.} =
    #defer: dump await c.db.killCursors(c.name, @[cursorId])
    let insertlen = 100
    var insertops = newseq[Future[WriteResult]](insertlen)
    let nao = now().toTime
    for i in 0 ..< insertlen:
      discard sleepAsync 1_000
      insertops[i] = c.insert(@[
        bson {
          insertedAt: nao,
          character: "Est",
          `type`: "Sword",
          attribute: "Holy-Demon",
          insertCount: i+1,
        }
      ])
    asyncCheck all(insertops)
    discard sleepAsync 1_000
    #dump await c.db.killCursors(c.name, @[cursorId])
    discard await c.remove(bson(), justone = true)

  suite "Change Stream tests":
    test "Prepare for running replica":
      require createMongoTemp()
      require createSSLCert()

    var p: seq[Process]
    spawn fakeDnsServer()
    test "Setting up replica set":
      p = setupMongoReplication()
      var m = newMongo(
        MongoUri &"mongodb://{mongoServer}:{replicaPortStart}/admin?ssl=true",
        poolconn = 1)
      require waitfor m.connect()
      check m.setReplica()
      sleep 15_000 # to ensure replica sets has enough time to elect primary

    var mongo = newMongo(
      MongoUri "mongodb+srv://localhost/",
      dnsport = dnsport,
      dnsserver = "localhost",
      poolconn = 2)

    test "Reconnect for replica set clients":
      require waitfor mongo.connect()

    var coll: Collection
    test "Watch collection temptest.templog":
      coll = mongo["temptest"]["templog"]
      var cWatch: Cursor
      try:
        cWatch = waitfor coll.watch()
      except:
        echo getCurrentExceptionMsg()
        fail()

      var lastChange: ChangeStream
      waitfor all([
        cWatch.forEach(proc(cs: ChangeStream) = lastChange = cs, stopWhen = {csDelete}),
        coll.inserting(cWatch.id)
      ])
      let count = waitfor coll.count()
      let lastDoc = waitfor coll.findOne(bson(), sort = bson { "_id": -1 })
      check count == 99
      check lastChange.operationType == csDelete
      check lastDoc["insertCount"] == 100

    test "Cleanup the temptest.templog":
      var res = waitfor coll.drop
      res.success.reasonedCheck("drop collection", res.reason)

    cleanResources p