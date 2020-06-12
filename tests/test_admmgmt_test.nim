import unittest, asyncdispatch, strformat
import osproc, os

import testutils
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
  var mongo: Mongo
  var db: Database
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
    let dbs = waitFor db.listDatabases
    check(dbs.len > 0)

  test "List database names":
    require db != nil
    dbs = waitFor db.listDatabaseNames
    check dbs.len > 0
    check db.name in dbs

  test &"Change to {newdb} db":
    require db != nil
    db.name = newdb
    check(db.name notin dbs)

  test &"List collections name on {db.name}":
    require db != nil
    colls = waitFor db.listCollectionNames
    check colls.len == 0

  test &"Create collection {targetColl} on {db.name}":
    require db != nil
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
    wr = waitFor db.renameCollection("notexists", newtgcoll)
    check not wr.success
    wr = waitFor db.renameCollection(targetColl, newtgcoll)
    require wr.success
    if not wr.success:
      "rename collection failed: ".tell wr.reason
    check newtgcoll notin colls
  test &"Drop collection {db.name}.{newtgcoll}":
    wr = waitFor db.dropCollection(targetColl)
    check not wr.success # already renamed to newgtcoll
    wr = waitFor db.dropCollection(newtgcoll)
    wr.success.reasonedCheck("dropCollection error", wr.reason)

  test &"Drop database {db.name}":
    require db != nil
    wr = waitFor db.dropDatabase
    wr.success.reasonedCheck("dropDatabase", wr.reason)

  test "Shutdown mongo":
    if runlocal:
      require mongo != nil
      wr = waitFor mongo.shutdown(timeout = 10)
      check wr.success
    else:
      skip()

  close mongo
  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun