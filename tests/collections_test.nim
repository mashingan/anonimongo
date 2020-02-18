import unittest, os, osproc, strformat, times, sequtils, sugar

import testutils
import ../src/anonimongo
import ../src/anonimongo/collections

{.warning[UnusedImport]: off.}

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

  test &"Create index on {namespace}":
    skip()

  test &"Count documents on {namespace}":
    check insertDocs.len == waitfor coll.count()

  test &"Distinct documents on {namespace}":
    require coll != nil
    let values = waitFor coll.`distinct`("type")
    check values.len == 1
    check values[0].kind == bkString

  test &"Find one query on {namespace}":
    let doc = waitfor coll.findOne(bson({ countId: 5 }))
    check doc["countId"] == 5
    check doc["type"] == "insertTest"
    check doc["addedTime"] == (currtime + initDuration(minutes = 5 * 10))

  test &"Find all on {namespace}":
    let docs = waitfor coll.findAll(sort = bson({ countId: -1 }))
    let dlen = docs.len
    check dlen == insertDocs.len
    for i in 0 .. docs.high:
      check docs[i]["countId"] == dlen-i-1

  test &"Find iterate on {namespace}":
    var count = 0
    for d in waitfor coll.findIter():
      check d["countId"] == count
      inc count

  test &"Remove countId 1 and 5 on {namespace}":
    let toremove = [1, 5]
    let (success, removed) = waitfor coll.remove(bson({
      countId: { "$in": toremove.map toBson },
    }))
    check success
    check toremove.len == removed

  test &"FindAndModify countId 8 to be 80 on {namespace}":
    require coll != nil
    let oldcount = 8
    let newcount = 80
    let olddoc = waitfor coll.findAndModify(query = bson({
      countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    dump olddoc
    check olddoc["countId"] == oldcount
    let newdoc = waitFor coll.findOne(bson({ countId: newcount }))
    check newdoc["countId"] == newcount

  test &"Update countId 9 $inc by 90 on {namespace}":
    let addcount = 90
    let oldcount = 9
    let newtype = "異世界召喚"
    let olddoc = waitFor coll.findOne(bson({ countId: oldcount }))
    let (success, count) = waitfor coll.update(
      bson({ countId: oldcount }),
      bson({ "$set": { "type": newtype }, "$inc": { countId: addcount }}),
      bson({ upsert: false, multi: true}))
    check success
    check count == 1
    let newdoc = waitFor coll.findOne(bson({ countId: oldcount + addcount }))
    check newdoc["countId"] == olddoc["countId"] + addcount
    check newdoc["type"] == newtype
    check newdoc["addedTime"] == olddoc["addedTime"].ofTime

  test &"Drop indexes collection of {namespace}":
    skip()

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