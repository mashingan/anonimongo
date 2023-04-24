discard """
  
  action: "run"
  exitcode: 0
  
  # flags with which to run the test, delimited by `;`
  matrix: "--threads:on --d:ssl -d:anostreamable -d:release"
"""

const testChangeStreams {.booldefine.} = false

when testChangeStreams:
  from std/threadpool import spawn, sync
  from std/osproc import Process
  from std/os import sleep
  from std/strformat import `&`
  from std/times import now, toTime

  import utils_test, utils_replica
  import anonimongo


  proc cleanResources(p: seq[Process]) =
    cleanup p
    sleep 1_000
    cleanMongoTemp()
    cleanupSSL()

  const nim164up = (NimMajor, NimMinor, NimPatch) >= (1, 6, 4)
  var p: seq[Process]

  proc processKiller() {.noconv.} =
    cleanResources p

  when nim164up:
    from std/exitprocs import addExitProc
    addExitProc processKiller
  else:
    addQuitProc processKiller

  proc setReplica(m: Mongo[AsyncSocket]): bool =
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

  proc inserting(c: Collection[AsyncSocket], cursorId: int64) {.async.} =
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

  block: #"Change Stream tests":
    block: # "Prepare for running replica":
      require createMongoTemp()
      require createSSLCert()

    spawn fakeDnsServer()
    block: # "Setting up replica set":
      p = setupMongoReplication()
      var m = newMongo[AsyncSocket](
        MongoUri &"mongodb://{mongoServer}:{replicaPortStart}/admin?ssl=true",
        poolconn = 1)
      require waitfor m.connect()
      assert m.setReplica()
      sleep 15_000 # to ensure replica sets has enough time to elect primary

    var mongo = newMongo[AsyncSocket](
      MongoUri "mongodb+srv://localhost/",
      dnsport = dnsport,
      dnsserver = "localhost",
      poolconn = 2)

    block: # "Reconnect for replica set clients":
      require waitfor mongo.connect()

    var coll: Collection[AsyncSocket]
    block: # "Watch collection temptest.templog":
      coll = mongo["temptest"]["templog"]
      var cWatch: Cursor[AsyncSocket]
      try:
        cWatch = waitfor coll.watch()
      except CatchableError:
        echo getCurrentExceptionMsg()
        fail()

      var lastChange: ChangeStream
      waitfor all([
        cWatch.forEach(proc(cs: ChangeStream) = lastChange = cs, stopWhen = {csDelete}),
        coll.inserting(cWatch.id)
      ])
      let count = waitfor coll.count()
      let lastDoc = waitfor coll.findOne(bson(), sort = bson { "_id": -1 })
      assert count == 99
      assert lastChange.operationType == csDelete
      assert lastDoc["insertCount"] == 100

    block: # "Cleanup the temptest.templog":
      var res = waitfor coll.drop
      res.success.reasonedCheck("drop collection", res.reason)