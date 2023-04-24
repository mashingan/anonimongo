discard """
  
  action: "run"
  exitcode: 0
  
  # flags with which to run the test, delimited by `;`
  matrix: "--threads:on -d:ssl -d:anostreamable -d:release"
"""

import utils_test

const
  testReplication {.booldefine.} = false

when testReplication and defined(ssl):
  from threadpool import spawn, sync
  from times import now, toTime
  from os import sleep
  from strformat import `&`
  from osproc import Process, kill, running, close
  from sequtils import allIt, all, anyIt

  import utils_replica

  import anonimongo

  when utils_test.verbose:
    from sugar import dump

  const nim164up = (NimMajor, NimMinor, NimPatch) >= (1, 6, 4)
  var processes: seq[Process]

  proc processKiller() {.noconv.} =
    processes.cleanup
    sleep 3000
    cleanupSSL()
    cleanMongoTemp()

  when nim164up:
    from std/exitprocs import addExitProc
    addExitProc processKiller
  else:
    addQuitProc processKiller

  block: # "Replication, SSL, and SRV DNS seedlist lookup (mongodb+srv) tests":
    block: # "Initial test setup":
      require createMongoTemp()
    block: # "Create self-signing SSL key certificate":
      require createSSLCert()
    block: # "Run the local replication set db":
      processes = setupMongoReplication()
      require processes.allIt( it != nil )
      require processes.all running

    var mongo: Mongo[TheSock]
    var db: Database[TheSock]
    block: # "Catch error without SSL for SSL/TLS required connection":
      errcatch(IOError) do:
        var m = newMongo[TheSock](
          MongoUri &"mongodb://{mongoServer}:{replicaPortStart}/admin",
          poolconn = utils_test.poolconn)
        when anoSocketSync:
          assert m.connect()
        else:
          assert waitfor m.connect()
        m.close()

    block: # "Connect single uri":
      mongo = newMongo[TheSock](MongoUri uriSettingRepl,
        poolconn = utils_test.poolconn,
        dnsserver = mongoServer,
        dnsport = dnsport)
      require mongo != nil
      when anoSocketSync:
        require mongo.connect()
      else:
        require waitfor mongo.connect()
      db = mongo["admin"]
      require db != nil

    block: # "Setting up replication set":
      var config = bson({
        "_id": rsetName,
        members: [
          { "_id": 0, host: &"{mongoServer}:{replicaPortStart}", priority: 2 },
          { "_id": 1, host: &"{mongoServer}:{replicaPortStart+1}" },
          { "_id": 2, host: &"{mongoServer}:{replicaPortStart+2}" },
        ]
      })
      var reply: BsonDocument
      try:
        when anoSocketSync:
          reply = db.replSetInitiate(config)
        else:
          reply = waitfor db.replSetInitiate(config)
      except MongoError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      reply.reasonedCheck("replSetInitiate")
      try:
        when anoSocketSync:
          reply = db.replSetGetStatus
        else:
          reply = waitfor db.replSetGetStatus
      except MongoError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      when utils_test.verbose: dump reply
      reply.reasonedCheck("replSetGetStatus")
      assert reply["set"] == rsetName
      let members = reply["members"].ofArray
      assert members.len == 3
    sleep 15_000 # waiting the replica set to elect primary

    block: # "Connect with manual multi uri connections":
      mongo = newMongo[TheSock](
        MongoUri uriMultiManual,
        poolconn = utils_test.poolconn
      )
      require mongo != nil
      when anoSocketSync:
        assert mongo.connect
      else:
        assert waitfor mongo.connect
      db = mongo["admin"]
      when anoSocketSync:
        let cfg = db.replSetGetStatus
      else:
        let cfg = waitfor db.replSetGetStatus
      let members = cfg["members"].ofArray
      assert members.len == 3
      assert members.anyIt( it["stateStr"] == "PRIMARY" )
      mongo.close

    spawn fakeDnsServer()
    block: # "assert newMongo mongodb+srv scheme connection":
      try:
        mongo = newMongo[TheSock](
          MongoUri uriSrv,
          poolconn = utils_test.poolconn,
          dnsserver = mongoServer,
          dnsport = dnsport
        )
      except RangeError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      require mongo != nil
      when anoSocketSync:
        require mongo.connect
      else:
        require waitfor mongo.connect
      db = mongo["temptest"]
      require db != nil
    sync()

    var tempcoll = db["test"]
    let
      currtime = now().toTime
      msg = "こんにちは、isekai"
      truthy = true
      embedobj = bson({
        "type": "kawaii",
        name: "Est",
        form: "Sword",
      })

    # block: # "Reconnect to enable replication set writing":
    #   skip()
    #   mongo.slaveOk
    #   #require waitfor mongo.connect
    #   db = mongo["temptest"]
    #   require db != nil
    #   #sync()
    #   #mongo.slaveOk
    #   tempcoll = db["test"]
    #   assert true

    block: # "Retry inserting to database":
      tempcoll = db["test"]
      let b = bson({
        entry: currtime,
        msg: msg,
        truthness: truthy,
        embedded: embedobj,
      })
      when anoSocketSync:
        let wr = tempcoll.insert(@[b])
      else:
        let wr = waitfor tempcoll.insert(@[b])
      wr.success.reasonedCheck("Retry tempcoll.insert", wr.reason)

    # apparently in some mongodb version, there's this problem
    # https://dba.stackexchange.com/questions/179616/mongodb-hangs-up-on-shutdown
    # if the problem persists, this replication action block: # would be disabled.
    when anoSocketSync:
      discard mongo.shutdown(timeout = 10, force = true)
    else:
      discard waitfor mongo.shutdown(timeout = 10, force = true)
    mongo.close