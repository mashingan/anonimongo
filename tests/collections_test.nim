import unittest, os, osproc, strformat, times, sequtils, sugar

import testutils
import ../src/anonimongo

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
  var wr: WriteResult

  let currtime = now().toTime
  var insertDocs = newseq[BsonDocument](10)
  var resfind{.used.}: BsonDocument
  for i in 0 ..< 10:
    insertDocs[i] = bson({
        countId: i,
        addedTime: currtime + initDuration(minutes = i * 10),
        `type`: "insertTest",
    })
  let newdocs = @[
    bson({ "_id" : 1, "char" : "Brisbane", "class" : "monk", "lvl" : 4 }),
    bson({ "_id" : 2, "char" : "Eldon", "class" : "alchemist", "lvl" : 3 }),
    bson({ "_id" : 3, "char" : "Meldane", "class" : "ranger", "lvl" : 3 })]
  let ops = @[
    bson({ insertOne: { "document": { "_id": 4, "char": "Dithras", "class": "barbarian", "lvl": 4 } } }),
    bson({ insertOne: { "document": { "_id": 5, "char": "Taeln", "class": "fighter", "lvl": 3 } } }),
    bson({ updateOne : {
       "filter" : { "char" : "Eldon" },
       "update" : { "$set" : { "status" : "Critical Injury" } }
       }}),
    bson({ deleteOne : { "filter" : { "char" : "Brisbane"} } }),
    bson({ replaceOne : {
       "filter" : { "char" : "Meldane" },
       "replacement" : { "char" : "Tanys", "class" : "oracle", "lvl": 4 }
    } })
  ]

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
    wr = waitfor coll.insert(insertDocs)
    check wr.success
    check wr.n == insertDocs.len

  test &"Create index on {namespace}":
    skip()

  test &"Count documents on {namespace}":
    check insertDocs.len == waitfor coll.count()

  test &"Distinct documents on {namespace}":
    require coll != nil
    let values = waitFor coll.`distinct`("type")
    check values.len == 1
    check values[0].kind == bkString

  test &"Aggregate documents on {namespace}":
    require coll != nil
    let tensOfMinutes = 5
    let lesstime = currtime + initDuration(minutes = tensOfMinutes * 10)
    let pipeline = @[
      bson({ "$match": { addedTime: { "$gte": currtime, "$lt": lesstime }}}),
      bson({ "$project": {
        addedTime: { "$dateToString": {
          date: "$addedTime",
          format: "%G-%m-%dT-%H:%M:%S%z",
          timezone: "+07:00", }}}})
    ]
    let aggfind = waitfor coll.aggregate(pipeline)
    check aggfind.len == tensOfMinutes

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
    wr = waitfor coll.remove(bson({
      countId: { "$in": toremove.map toBson },
    }))
    check wr.success
    check toremove.len == wr.n

  test &"FindAndModify countId 8 to be 80 on {namespace}":
    require coll != nil
    let oldcount = 8
    let newcount = 80
    let olddoc = waitfor coll.findAndModify(query = bson({
      countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    check olddoc["countId"] == oldcount
    let newdoc = waitFor coll.findOne(bson({ countId: newcount }))
    check newdoc["countId"] == newcount

  test &"Update countId 9 $inc by 90 on {namespace}":
    let addcount = 90
    let oldcount = 9
    let newtype = "異世界召喚"
    let olddoc = waitFor coll.findOne(bson({ countId: oldcount }))
    wr = waitfor coll.update(
      bson({ countId: oldcount }),
      bson({ "$set": { "type": newtype }, "$inc": { countId: addcount }}),
      bson({ upsert: false, multi: true}))
    check wr.success
    check wr.n == 1
    let newdoc = waitFor coll.findOne(bson({ countId: oldcount + addcount }))
    check newdoc["countId"] == olddoc["countId"] + addcount
    check newdoc["type"] == newtype
    check newdoc["addedTime"] == olddoc["addedTime"].ofTime

  test &"Drop indexes collection of {namespace}":
    skip()

  test &"Bulk write ordered collection of {namespace}":
    expect MongoError:
      discard waitfor coll.bulkWrite(@[
        bson({ invalidCommandField: bson() })
      ])
    wr = waitfor coll.insert(newdocs)
    wr.success.reasonedCheck("insert newdocs", wr.reason)

    var bulkres = waitfor coll.bulkWrite(ops)
    check bulkres.nInserted == 2
    check bulkres.nRemoved == 1
    check bulkres.nModified == 2
    check bulkres.writeErrors.len == 0

    # will error and stop in 2nd ops since it's ordered
    let _ = waitfor coll.remove(bson({ "_id": 4 }))
    bulkres = waitfor coll.bulkWrite(ops)
    check bulkres.nInserted == 1
    check bulkres.writeErrors.len == 1

  test &"Bulk write unordered collection of {namespace}":
    # clean up from previous input
    discard waitfor coll.remove(bson({
      "char": { "$ne": bsonNull() }
    }))
    check (waitfor coll.count()) == 8
    discard waitfor coll.insert(newdocs)
    var bulkres = waitfor coll.bulkWrite(ops, ordered = false)
    check bulkres.nInserted == 2
    check bulkres.nRemoved == 1
    check bulkres.nModified == 2
    check bulkres.writeErrors.len == 0

    # will give error at 2nd op but continue with other ops because ordered false
    discard waitfor coll.remove(bson({
      "char": { "$ne": bsonNull() }
    }))
    check (waitfor coll.count()) == 8
    discard waitfor coll.insert(newdocs)
    discard waitfor coll.insert(@[bson({ "_id": 5, "char": "Taeln", "class": "fighter", "lvl": 3 })])
    bulkres = waitfor coll.bulkWrite(ops, ordered = false)
    check bulkres.nInserted == 1
    check bulkres.nRemoved == 1
    check bulkres.nModified == 2
    check bulkres.writeErrors.len == 1

  test &"Drop collection {coll.db.name}.{targetColl}":
    require coll != nil
    wr = waitFor coll.drop
    wr.success.reasonedCheck("collections.drop error", wr.reason)

  test &"Drop database {coll.db.name}":
    require coll != nil
    wr = waitFor coll.db.dropDatabase
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