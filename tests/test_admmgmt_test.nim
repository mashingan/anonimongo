import unittest, asyncdispatch, strformat
import osproc, os

import utils_test
import anonimongo

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "Administration APIs tests":
  test "Require mongorun is running":
    if runlocal:
      require(mongorun.running)
    else:
      check true

  let targetColl = "testtemptest"
  let newtgcoll = "newtemptest"
  let newdb = "newtemptest"
  var mongo: Mongo[TheSock]
  var db: Database[TheSock]
  var dbs: seq[string]
  var colls: seq[string]
  var wr: WriteResult
  test "Connect to localhost and authentication":
    mongo = testsetup()
    require(mongo != nil)
    if mongo.withAuth:
      require(mongo.authenticated)
  test "Get admin database":
    require mongo != nil
    db = mongo["admin"]
    require not db.isNil
    check db.name == "admin"

  test "List databases in BsonBase":
    require db != nil
    when anoSocketSync:
      let dbs = db.listDatabases
    else:
      let dbs = waitFor db.listDatabases
    check(dbs.len > 0)

  test "List database names":
    require db != nil
    when anoSocketSync:
      dbs = db.listDatabaseNames
    else:
      dbs = waitFor db.listDatabaseNames
    check dbs.len > 0
    check db.name in dbs

  test &"Change to {newdb} db":
    require db != nil
    db.name = newdb
    check(db.name notin dbs)

  test &"List collections name on {db.name}":
    require db != nil
    when anoSocketSync:
      colls = db.listCollectionNames
    else:
      colls = waitFor db.listCollectionNames
    check colls.len == 0

  test &"Create collection {targetColl} on {db.name}":
    require db != nil
    when anoSocketSync:
      wr = db.create(targetColl)
    else:
      wr = waitFor db.create(targetColl)
    wr.success.reasonedCheck("create error", wr.reason)
    check targetColl notin colls
    colls.add targetColl

  test &"Create indexes on {db.name}.{targetColl}":
    skip()
  test &"List indexes on {db.name}.{targetColl}":
    #let indexes = waitFor db.listIndexes(targetColl)
    skip()
  test &"Rename collection {targetColl} to {newtgcoll}":
    require db != nil
    when anoSocketSync:
      wr = db.renameCollection("notexists", newtgcoll)
    else:
      wr = waitFor db.renameCollection("notexists", newtgcoll)
    check not wr.success
    when anoSocketSync:
      wr = db.renameCollection(targetColl, newtgcoll)
    else:
      wr = waitFor db.renameCollection(targetColl, newtgcoll)
    require wr.success
    if not wr.success:
      "rename collection failed: ".tell wr.reason
    check newtgcoll notin colls
  test &"Drop collection {db.name}.{newtgcoll}":
    when anoSocketSync:
      wr = db.dropCollection(targetColl)
    else:
      wr = waitFor db.dropCollection(targetColl)
    check true # check wr.success was false before, but looks like it is ok in mongo 7.0.1
    when anoSocketSync:
      wr = db.dropCollection(newtgcoll)
    else:
      wr = waitFor db.dropCollection(newtgcoll)
    wr.success.reasonedCheck("dropCollection error", wr.reason)

  test &"Drop database {db.name}":
    require db != nil
    when anoSocketSync:
      wr = db.dropDatabase
    else:
      wr = waitFor db.dropDatabase
    wr.success.reasonedCheck("dropDatabase", wr.reason)

  test "Shutdown mongo":
    if runlocal:
      require mongo != nil
      when anoSocketSync:
        wr = mongo.shutdown(timeout = 10)
      else:
        wr = waitFor mongo.shutdown(timeout = 10)
      check wr.success
    else:
      skip()

  close mongo
  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun