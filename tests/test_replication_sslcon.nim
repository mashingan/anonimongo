# WIP replication test
# TODO:
# 1. [Done] Run local mongod processes for replication setup
# 2. [Done] Manage the replication setup by initializing it first
#    ref: https://docs.mongodb.com/manual/tutorial/deploy-replica-set-for-testing/
# 3. [Done] Fix all nodes status to be able to elect the PRIMARY, current problem
#    all nodes are SECONDARY and this disability to elect the PRIMARY cannot
#    to do any write operation
# 4. Fix weird `auto` enabling slave during the test and it should be throwing
#    MongoError with reason `not enabled slave`.
# 5. [Done] Cleanup all produced artifacts such as temporary dbpath directories and
#    created self-signing key, certificate, and pem file.
# 6. [Done w ReadPreference.primary?] Since the test purposely choose
#    the ReadPreference.secondary, testing to read the database entry
#    could result in disaster because of eventual synchronization.

import utils_test

{.warning[UnusedImport]: off.}

const
  testReplication {.booldefine.} = false

when testReplication and defined(ssl):
  import unittest
  from threadpool import spawn, sync
  from times import now, toTime
  from os import sleep
  from strformat import `&`
  from osproc import Process, running
  from sequtils import allIt, all, anyIt
  when utils_test.verbose:
    from sugar import dump

  import utils_replica

  import anonimongo

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


  suite "Replication, SSL, and SRV DNS seedlist lookup (mongodb+srv) tests":
    test "Initial test setup":
      require createMongoTemp()
    test "Create self-signing SSL key certificate":
      require createSSLCert()
    test "Run the local replication set db":
      processes = setupMongoReplication()
      require processes.allIt( it != nil )
      require processes.all running

    var mongo: Mongo[TheSock]
    var db: Database[TheSock]
    test "Catch error without SSL for SSL/TLS required connection":
      expect(IOError):
        var m = newMongo[TheSock](
          MongoUri &"mongodb://{mongoServer}:{replicaPortStart}/admin",
          poolconn = utils_test.poolconn)
        when anoSocketSync:
          check m.connect()
        else:
          check waitfor m.connect()
        m.close()

    test "Connect single uri":
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

    test "Setting up replication set":
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
      check reply["set"] == rsetName
      let members = reply["members"].ofArray
      check members.len == 3
    sleep 15_000 # waiting the replica set to elect primary

    test "Connect with manual multi uri connections":
      mongo = newMongo[TheSock](
        MongoUri uriMultiManual,
        poolconn = utils_test.poolconn
      )
      require mongo != nil
      when anoSocketSync:
        check mongo.connect
      else:
        check waitfor mongo.connect
      db = mongo["admin"]
      when anoSocketSync:
        let cfg = db.replSetGetStatus
      else:
        let cfg = waitfor db.replSetGetStatus
      let members = cfg["members"].ofArray
      check members.len == 3
      check members.anyIt( it["stateStr"] == "PRIMARY" )
      mongo.close

    spawn fakeDnsServer()
    test "Check newMongo mongodb+srv scheme connection":
      try:
        mongo = newMongo[TheSock](
          MongoUri uriSrv,
          poolconn = utils_test.poolconn,
          dnsserver = mongoServer,
          dnsport = dnsport
        )
      except RangeDefect:
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

    test "Reconnect to enable replication set writing":
      skip()
      mongo.slaveOk
      #require waitfor mongo.connect
      db = mongo["temptest"]
      require db != nil
      #sync()
      #mongo.slaveOk
      tempcoll = db["test"]
      check true

    test "Retry inserting to database":
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
    # if the problem persists, this replication action test would be disabled.
    when anoSocketSync:
      discard mongo.shutdown(timeout = 10, force = true)
    else:
      discard waitfor mongo.shutdown(timeout = 10, force = true)
    mongo.close