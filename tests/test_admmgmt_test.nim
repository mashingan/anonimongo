discard """
  
  action: "run"
  exitcode: 0
  
  # flags with which to run the test, delimited by `;`
  matrix: "-d:anostreamable -d:danger"
"""

import asyncdispatch
from std/osproc import Process, kill, close, running
from std/os import sleep

import ./utils_test
import anonimongo

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

block: # "Administration APIs tests":
  block: # "Require mongorun is running":
    if runlocal:
      require(mongorun.running)
    else:
      assert true

  let targetColl = "testtemptest"
  let newtgcoll = "newtemptest"
  let newdb = "newtemptest"
  var mongo: Mongo[TheSock]
  var db: Database[TheSock]
  var dbs: seq[string]
  var colls: seq[string]
  var wr: WriteResult
  block: # "Connect to localhost and authentication":
    mongo = testsetup()
    require(mongo != nil)
    if mongo.withAuth:
      require(mongo.authenticated)
  block: # "Get admin database":
    require mongo != nil
    db = mongo["admin"]
    require not db.isNil
    assert db.name == "admin"

  block: # "List databases in BsonBase":
    require db != nil
    when anoSocketSync:
      let dbs = db.listDatabases
    else:
      let dbs = waitFor db.listDatabases
    assert dbs.len > 0

  block: # "List database names":
    require db != nil
    when anoSocketSync:
      dbs = db.listDatabaseNames
    else:
      dbs = waitFor db.listDatabaseNames
    assert dbs.len > 0
    assert db.name in dbs

  block: # &"Change to {newdb} db":
    require db != nil
    db.name = newdb
    assert db.name notin dbs

  block: # &"List collections name on {db.name}":
    require db != nil
    when anoSocketSync:
      colls = db.listCollectionNames
    else:
      colls = waitFor db.listCollectionNames
    assert colls.len == 0

  block: # &"Create collection {targetColl} on {db.name}":
    require db != nil
    when anoSocketSync:
      wr = db.create(targetColl)
    else:
      wr = waitFor db.create(targetColl)
    wr.success.reasonedCheck("create error", wr.reason)
    assert targetColl notin colls
    colls.add targetColl

  block: # &"Create indexes on {db.name}.{targetColl}":
    skip()
  block: # &"List indexes on {db.name}.{targetColl}":
    #let indexes = waitFor db.listIndexes(targetColl)
    skip()
  block: # &"Rename collection {targetColl} to {newtgcoll}":
    require db != nil
    when anoSocketSync:
      wr = db.renameCollection("notexists", newtgcoll)
    else:
      wr = waitFor db.renameCollection("notexists", newtgcoll)
    assert not wr.success
    when anoSocketSync:
      wr = db.renameCollection(targetColl, newtgcoll)
    else:
      wr = waitFor db.renameCollection(targetColl, newtgcoll)
    require wr.success
    if not wr.success:
      "rename collection failed: ".tell wr.reason
    assert newtgcoll notin colls
  block: # &"Drop collection {db.name}.{newtgcoll}":
    when anoSocketSync:
      wr = db.dropCollection(targetColl)
    else:
      wr = waitFor db.dropCollection(targetColl)
    assert not wr.success # already renamed to newgtcoll
    when anoSocketSync:
      wr = db.dropCollection(newtgcoll)
    else:
      wr = waitFor db.dropCollection(newtgcoll)
    wr.success.reasonedCheck("dropCollection error", wr.reason)

  block: # &"Drop database {db.name}":
    require db != nil
    when anoSocketSync:
      wr = db.dropDatabase
    else:
      wr = waitFor db.dropDatabase
    wr.success.reasonedCheck("dropDatabase", wr.reason)

  block: # "Shutdown mongo":
    if runlocal:
      require mongo != nil
      when anoSocketSync:
        wr = mongo.shutdown(timeout = 10)
      else:
        wr = waitFor mongo.shutdown(timeout = 10)
      assert wr.success
    else:
      skip()

  close mongo
  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun