import unittest, sugar, asyncdispatch, strformat
import osproc, os
import testutils, admmgmt, bson, types, pool, wire

proc tell(label, reason: string) =
  stdout.write label
  dump reason

suite "Administration APIs tests":
  var mongorun = startmongo()
  sleep 1000

  let targetColl = "testtemptest"
  let newtgcoll = "newtemptest"
  let newdb = "newtemptest"
  var mongo: Mongo
  var db: Database
  var dbs: seq[string]
  var colls: seq[string]
  test "Require mongorun is running":
    require(mongorun.running)
  test "Connect to localhost and authentication":
    mongo = testsetup()
    require(mongo.authenticated)
  test "Get admin database":
    db = mongo["admin"]
    require not db.isNil
    check db.name == "admin"

  test "List databases in BsonBase":
    let dbs = waitFor db.listDatabases
    check(dbs.len > 0)

  test "List database names":
    dbs = waitFor db.listDatabaseNames
    check dbs.len > 0
    check db.name in dbs

  test &"Change to {newdb} db":
    db.name = newdb
    check(db.name notin dbs)

  test &"List collections name on {db.name}":
    colls = waitFor db.listCollectionNames
    check colls.len == 0

  test &"Create collection {targetColl} on {db.name}":
    let (success, reason) = waitFor db.create(targetColl)
    check success
    check targetColl notin colls
    colls.add targetColl
    if not success:
      "create collection failed: ".tell reason

  test &"Create indexes on {db.name}.{targetColl}":
    skip()
  test &"List indexes on {db.name}.{targetColl}":
    #let indexes = waitFor db.listIndexes(targetColl)
    skip()
  test &"Rename collection {targetColl} to {newtgcoll}":
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
    check success
    if not success:
      "drop collection failed: ".tell reason

  test &"Drop database {db.name}":
    let (success, reason) = waitFor db.dropDatabase
    check success
    if not success:
      "drop database failed: ".tell reason

#[
  if mongo.authenticated:
    for db in waitFor mongo.listDatabases:
      dump db
    var db = mongo["admin"]
    let targetColl = "testtemptest"
    let newtgcoll = "newtemptest"
    # test create collection
    db.name = "temptest"
    for index in waitFor db.listIndexes("role"):
      dump index
    var (success, reason) = waitFor db.create(targetColl)
    if not success:
      echo "Cannot create collection: ", reason
    else:
      echo "successfully create collection", targetColl

    for c in waitFor db.listCollections(filter = bson({
      idIndex: 1, info: 1, options: 1
    })):
      dump c

    (success, reason) = waitFor db.renameCollection(targetColl, newtgcoll)
    if not success:
      echo &"Cannot rename collection from {targetColl} to {newtgcoll}: {reason}"
    else:
      echo &"successfully rename from {targetColl} to {newtgcoll}"

    for name in waitFor db.listCollectionNames:
      dump name

    (success, reason) = waitFor db.dropCollection(newtgcoll)
    if not success:
      echo &"Cannot drop collection {newtgcoll}: {reason}"
    else:
      echo &"Collection {newtgcoll} dropped"

    for currname in waitFor db.listCollectionNames:
      dump currname

    (success, reason) = waitFor mongo.shutdown(timeout = 10)
    dump success
    #dump reason

    ]#
    close mongo.pool
    kill mongorun