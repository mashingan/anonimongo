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
  from threadpool import spawn
  from sequtils import allIt, all, anyIt
  from sugar import dump

  import utils_replica

  import anonimongo

  suite "Replication, SSL, and SRV DNS seedlist lookup (mongodb+srv) tests":
    test "Initial test setup":
      require createMongoTemp()
    test "Create self-signing SSL key certificate":
      require createSSLCert()
    var processes: seq[Process]
    test "Run the local replication set db":
      processes = setupMongoReplication()
      require processes.allIt( it != nil )
      require processes.all running

    var mongo: Mongo
    var db: Database
    test "Catch error without SSL for SSL/TLS required connection":
      expect(IOError):
        var m = newMongo(
          MongoUri &"mongodb://{mongoServer}:{replicaPortStart}/admin",
          poolconn = utils_test.poolconn)
        check waitfor m.connect()
        m.close()

    test "Connect single uri":
      mongo = newMongo(MongoUri uriSettingRepl,
        poolconn = utils_test.poolconn,
        dnsserver = mongoServer,
        dnsport = dnsport)
      require mongo != nil
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
        reply = waitfor db.replSetInitiate(config)
      except MongoError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      reply.reasonedCheck("replSetInitiate")
      try:
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
      mongo = newMongo(
        MongoUri uriMultiManual,
        poolconn = utils_test.poolconn
      )
      require mongo != nil
      check waitfor mongo.connect
      db = mongo["admin"]
      let cfg = waitfor db.replSetGetStatus
      let members = cfg["members"].ofArray
      check members.len == 3
      check members.anyIt( it["stateStr"] == "PRIMARY" )
      mongo.close

    spawn fakeDnsServer()
    test "Check newMongo mongodb+srv scheme connection":
      try:
        mongo = newMongo(
          MongoUri uriSrv,
          poolconn = utils_test.poolconn,
          dnsserver = mongoServer,
          dnsport = dnsport
        )
      except RangeError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      require mongo != nil
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
      let wr = waitfor tempcoll.insert(@[b])
      wr.success.reasonedCheck("Retry tempcoll.insert", wr.reason)

    discard waitfor mongo.shutdown(timeout = 10)
    mongo.close
    processes.cleanup
    sleep 3000
    cleanupSSL()
    cleanMongoTemp()