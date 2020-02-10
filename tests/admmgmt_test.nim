import unittest, asyncdispatch, strformat
import osproc, os

import testutils
import dbops/admmgmt
import core/[bson, types, wire]

const localhost = testutils.host == "localhost"

var mongorun: Process
if localhost:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "Administration APIs tests":
  test "Require mongorun is running":
    if localhost:
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
  test "Connect to localhost and authentication":
    mongo = testsetup()
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
    let (success, reason) = waitFor db.create(targetColl)
    success.reasonedCheck("create error", reason)
    check targetColl notin colls
    colls.add targetColl

  test &"Create indexes on {db.name}.{targetColl}":
    skip()
  test &"List indexes on {db.name}.{targetColl}":
    #let indexes = waitFor db.listIndexes(targetColl)
    skip()
  test &"Rename collection {targetColl} to {newtgcoll}":
    require db != nil
    var (success, reason) = waitFor db.renameCollection("notexists", newtgcoll)
    check not success
    (success, reason) = waitFor db.renameCollection(targetColl, newtgcoll)
    require success
    if not success:
      "rename collection failed: ".tell reason
    check newtgcoll notin colls
  test &"Drop collection {db.name}.{newtgcoll}":
    var (success, reason) = waitFor db.dropCollection(targetColl)
    check not success # already renamed to newgtcoll
    (success, reason) = waitFor db.dropCollection(newtgcoll)
    success.reasonedCheck("dropCollection error", reason)

  test &"Drop database {db.name}":
    require db != nil
    let (success, reason) = waitFor db.dropDatabase
    success.reasonedCheck("dropDatabase", reason)

  test "Shutdown mongo":
    require mongo != nil
    let (success, _) = waitFor mongo.shutdown(timeout = 10)
    check success

  close mongo
  if localhost:
    if mongorun.running: kill mongorun
    close mongorun