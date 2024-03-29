import unittest, os, osproc, strformat, times, sequtils, sugar

import utils_test
import anonimongo

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

  var mongo: Mongo[TheSock]
  let targetColl = "testtemptest"
  var coll: Collection[TheSock]
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
    if mongo.withAuth:
      require(mongo.authenticated)
  
  test &"Implicitly create a db {newdb} and collection {targetColl}":
    # we implicitly create a new db and collection
    coll = mongo[newdb][targetColl]
    namespace = &"{coll.db.name}.{coll.name}"
    check namespace == &"{newdb}.{targetColl}"

  test &"Insert documents on {namespace}":
    require coll != nil
    when anoSocketSync:
      wr = coll.insert(insertDocs)
    else:
      wr = waitfor coll.insert(insertDocs)
    check wr.success
    check wr.n == insertDocs.len

  test &"Create index on {namespace}":
    when anoSocketSync:
      wr = coll.createIndex(bson({
        countId: 1, addedTime: 1
      }))
    else:
      wr = waitfor coll.createIndex(bson({
        countId: 1, addedTime: 1
      }))
    wr.success.reasonedCheck("Create index error", wr.reason)

  test &"List indexes on {namespace}":
    when anoSocketSync:
      let indexes = coll.listIndexes
    else:
      let indexes = waitfor coll.listIndexes
    check indexes.len > 1

  test &"Count documents on {namespace}":
    when anoSocketSync:
      check insertDocs.len == coll.count()
    else:
      check insertDocs.len == waitfor coll.count()

  test &"Distinct documents on {namespace}":
    require coll != nil
    when anoSocketSync:
      let values = coll.`distinct`("type")
    else:
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
    let opt = bson {
      allowDiskUse: true,
      maxTimeMS: 100,
      readConcern: { level: "majority" },
    }
    when anoSocketSync:
      let aggfind = coll.aggregate(pipeline, opt)
    else:
      let aggfind = waitfor coll.aggregate(pipeline, opt)
    check aggfind.len == tensOfMinutes

  test &"Find one query on {namespace}":
    when anoSocketSync:
      let doc = coll.findOne(bson({ countId: 5 }))
    else:
      let doc = waitfor coll.findOne(bson({ countId: 5 }))
    check doc["countId"] == 5
    check doc["type"] == "insertTest"
    check doc["addedTime"] == (currtime + initDuration(minutes = 5 * 10))

  test &"Find all on {namespace}":
    when anoSocketSync:
      var docs = coll.findAll(sort = bson({ countId: -1 }))
    else:
      var docs = waitfor coll.findAll(sort = bson({ countId: -1 }))
    let dlen = docs.len
    check dlen == insertDocs.len
    for i in 0 .. docs.high:
      check docs[i]["countId"] == dlen-i-1

    let limit = 5
    when anoSocketSync:
      docs = coll.findAll(bson(), limit = 5)
    else:
      docs = waitfor coll.findAll(bson(), limit = 5)
    check docs.len == limit

  test &"Find iterate on {namespace}":
    var count = 0
    when anoSocketSync:
      for d in coll.findIter():
        check d["countId"] == count
        inc count
    else:
      for d in waitfor coll.findIter():
        check d["countId"] == count
        inc count

  test &"Remove countId 1 and 5 on {namespace}":
    let toremove = [1, 5]
    when anoSocketSync:
      wr = coll.remove(bson({
        countId: { "$in": toremove.map toBson },
      }))
    else:
      wr = waitfor coll.remove(bson({
        countId: { "$in": toremove.map toBson },
      }))
    check wr.success
    check toremove.len == wr.n

  test &"FindAndModify countId 8 to be 80 on {namespace}":
    require coll != nil
    let oldcount = 8
    let newcount = 80
    when anoSocketSync:
      let olddoc = coll.findAndModify(query = bson({
        countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    else:
      let olddoc = waitfor coll.findAndModify(query = bson({
        countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    check olddoc["countId"] == oldcount
    when anoSocketSync:
      let newdoc = coll.findOne(bson({ countId: newcount }))
    else:
      let newdoc = waitFor coll.findOne(bson({ countId: newcount }))
    check newdoc["countId"] == newcount

  test &"Update countId 9 $inc by 90 on {namespace}":
    let addcount = 90
    let oldcount = 9
    let newtype = "異世界召喚"
    when anoSocketSync:
      let olddoc = coll.findOne(bson({ countId: oldcount }))
    else:
      let olddoc = waitFor coll.findOne(bson({ countId: oldcount }))
    when anoSocketSync:
      wr = coll.update(
        bson({ countId: oldcount }),
        bson({ "$set": { "type": newtype }, "$inc": { countId: addcount }}),
        bson({ upsert: false, multi: true}))
    else:
      wr = waitfor coll.update(
        bson({ countId: oldcount }),
        bson({ "$set": { "type": newtype }, "$inc": { countId: addcount }}),
        bson({ upsert: false, multi: true}))
    check wr.success
    check wr.n == 1
    when anoSocketSync:
      let newdoc = coll.findOne(bson({ countId: oldcount + addcount }))
    else:
      let newdoc = waitFor coll.findOne(bson({ countId: oldcount + addcount }))
    check newdoc["countId"] == olddoc["countId"] + addcount
    check newdoc["type"] == newtype
    check newdoc["addedTime"] == olddoc["addedTime"].ofTime

  test &"Drop index collection of {namespace}":
    when anoSocketSync:
      wr = coll.dropIndex("countId_1_addedTime_1_")
    else:
      wr = waitfor coll.dropIndex("countId_1_addedTime_1_")
    wr.success.reasonedCheck("Drop index name error", wr.reason)
    # this time removing using index specification document
    when anoSocketSync:
      discard coll.createIndex(bson({
        countId: 1, addedTime: 1
      }))
      wr = coll.dropIndex(bson({
        countId: 1, addedTime: 1
      }))
    else:
      discard waitfor coll.createIndex(bson({
        countId: 1, addedTime: 1
      }))
      wr = waitfor coll.dropIndex(bson({
        countId: 1, addedTime: 1
      }))
    wr.success.reasonedCheck("Drop index keys error", wr.reason)

  test &"Bulk write ordered collection of {namespace}":
    expect MongoError:
      when anoSocketSync:
        discard coll.bulkWrite(@[
          bson({ invalidCommandField: bson() })
        ])
      else:
        discard waitfor coll.bulkWrite(@[
          bson({ invalidCommandField: bson() })
        ])
    
    when anoSocketSync:
      wr = coll.insert(newdocs)
    else:
      wr = waitfor coll.insert(newdocs)
    wr.success.reasonedCheck("insert newdocs", wr.reason)

    when anoSocketSync:
      var bulkres = coll.bulkWrite(ops)
    else:
      var bulkres = waitfor coll.bulkWrite(ops)
    check bulkres.nInserted == 2
    check bulkres.nRemoved == 1
    check bulkres.nModified == 2
    check bulkres.writeErrors.len == 0

    # will error and stop in 2nd ops since it's ordered
    when anoSocketSync:
      let _ = coll.remove(bson({ "_id": 4 }))
      bulkres = coll.bulkWrite(ops)
    else:
      let _ = waitfor coll.remove(bson({ "_id": 4 }))
      bulkres = waitfor coll.bulkWrite(ops)
    check bulkres.nInserted == 1
    check bulkres.writeErrors.len == 1

  test &"Bulk write unordered collection of {namespace}":
    # clean up from previous input
    when anoSocketSync:
      discard coll.remove(bson({
        "char": { "$ne": bsonNull() }
      }))
      check coll.count() == 8
      discard coll.insert(newdocs)
      var bulkres = coll.bulkWrite(ops, ordered = false)
    else:
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
    when anoSocketSync:
      discard coll.remove(bson({
        "char": { "$ne": bsonNull() }
      }))
      check coll.count() == 8
      discard coll.insert(newdocs)
      discard coll.insert(@[bson({ "_id": 5, "char": "Taeln", "class": "fighter", "lvl": 3 })])
      bulkres = coll.bulkWrite(ops, ordered = false)
    else:
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
    when anoSocketSync:
      wr = coll.drop
    else:
      wr = waitFor coll.drop
    wr.success.reasonedCheck("collections.drop error", wr.reason)

  test &"Drop database {coll.db.name}":
    require coll != nil
    when anoSocketSync:
      wr = coll.db.dropDatabase
    else:
      wr = waitFor coll.db.dropDatabase
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