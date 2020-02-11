import unittest, os, osproc, strformat, times

import testutils
import ../src/anonimongo
import ../src/anonimongo/collections

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "Collections APIs tests":
  test "Require mongorun is running":
    if runlocal:
      require(mongorun.running)
    else:
      check true

  var mongo: Mongo
  let targetColl = "testtemptest"
  var coll: Collection
  let newdb = "newtemptest"
  var namespace: string

  let currtime = now().toTime
  var insertDocs = newseq[BsonDocument](10)
  var resfind{.used.}: BsonDocument
  for i in 0 ..< 10:
    insertDocs[i] = bson({
        countId: i,
        addedTime: currtime + initDuration(minutes = i * 10),
        `type`: "insertTest",
    })

  test "Connect to localhost and authentication":
    mongo = testsetup()
    require(mongo != nil)
    require(mongo.authenticated)
  
  test &"Implicitly create a db {newdb} and collection {targetColl}":
    # we implicitly create a new db and collection
    coll = mongo[newdb][targetColl]
    namespace = &"{coll.db.name}.{coll.name}"
    check namespace == &"{newdb}.{targetColl}"

  test &"Insert documents on {namespace}":
    require coll != nil
    var (success, count) = waitfor coll.insert(insertDocs)
    check success
    check count == insertDocs.len

  test &"Count documents on {namespace}":
    check insertDocs.len == waitfor coll.count()

  test &"Drop collection {coll.db.name}.{targetColl}":
    require coll != nil
    var (success, reason) = waitFor coll.drop
    success.reasonedCheck("collections.drop error", reason)

  test &"Drop database {coll.db.name}":
    require coll != nil
    let (success, reason) = waitFor coll.db.dropDatabase
    success.reasonedCheck("dropDatabase", reason)

  test "Shutdown mongo":
    require mongo != nil
    let (success, _) = waitFor mongo.shutdown(timeout = 10)
    check success

  close mongo
  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun

#[
  try:
    var mongo = testsetup()
    var coll = mongo["temptest"]["role"]
    #[
    var q = coll.find()
    var curs = waitfor q.iter
    for d in curs:
    ]#
    for d in waitFor coll.findIter(
      sort = bson({ "_id": -1 })
    ):
      dump d
  except:
    echo getCurrentExceptionMsg()
  finally:
    kill mongorun
    close mongorun
    ]#