discard """
  
  action: "run"
  exitcode: 0
  
  # flags with which to run the test, delimited by `;`
  matrix: "-d:anostreamable -d:danger"
"""

from std/os import sleep
from std/osproc import Process, kill, running, close
from std/strformat import `&`
from std/times import now, toTime, initDuration, `+`

import utils_test
import anonimongo

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

const nim164up = (NimMajor, NimMinor, NimPatch) >= (1, 6, 4)
when nim164up:
  from std/exitprocs import addExitProc
  addExitProc proc() {.noconv.} =
    if runlocal:
      if mongorun.running: kill mongorun
      close mongorun
else:
  addQuitProc do:
    if runlocal:
      if mongorun.running: kill mongorun
      close mongorun


block: # "Collections APIs tests":
  block: # "Require mongorun is running":
    if runlocal:
      require(mongorun.running)
    else:
      assert true

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

  block: # "Connect to localhost and authentication":
    mongo = testsetup()
    require(mongo != nil)
    if mongo.withAuth:
      require(mongo.authenticated)
  
  block: # &"Implicitly create a db {newdb} and collection {targetColl}":
    # we implicitly create a new db and collection
    coll = mongo[newdb][targetColl]
    namespace = &"{coll.db.name}.{coll.name}"
    assert namespace == &"{newdb}.{targetColl}"
    when anoSocketSync:
      discard coll.drop
    else:
      discard waitFor coll.drop

  block: # &"Insert documents on {namespace}":
    require coll != nil
    when anoSocketSync:
      wr = coll.insert(insertDocs)
    else:
      wr = waitfor coll.insert(insertDocs)
    assert wr.success
    assert wr.n == insertDocs.len

  block: # &"Create index on {namespace}":
    when anoSocketSync:
      wr = coll.createIndex(bson({
        countId: 1, addedTime: 1
      }))
    else:
      wr = waitfor coll.createIndex(bson({
        countId: 1, addedTime: 1
      }))
    wr.success.reasonedCheck("Create index error", wr.reason)

  block: # &"List indexes on {namespace}":
    when anoSocketSync:
      let indexes = coll.listIndexes
    else:
      let indexes = waitfor coll.listIndexes
    assert indexes.len > 1

  block: # &"Count documents on {namespace}":
    when anoSocketSync:
      assert insertDocs.len == coll.count()
    else:
      assert insertDocs.len == waitfor coll.count()

  block: # &"Distinct documents on {namespace}":
    require coll != nil
    when anoSocketSync:
      let values = coll.`distinct`("type")
    else:
      let values = waitFor coll.`distinct`("type")
    assert values.len == 1, &"expect len 1, got {values.len}"
    assert values[0].kind == bkString

  block: # &"Aggregate documents on {namespace}":
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
    assert aggfind.len == tensOfMinutes

  block: # &"Find one query on {namespace}":
    when anoSocketSync:
      let doc = coll.findOne(bson({ countId: 5 }))
    else:
      let doc = waitfor coll.findOne(bson({ countId: 5 }))
    assert doc["countId"] == 5
    assert doc["type"] == "insertTest"
    assert doc["addedTime"] == (currtime + initDuration(minutes = 5 * 10))

  block: # &"Find all on {namespace}":
    when anoSocketSync:
      var docs = coll.findAll(sort = bson({ countId: -1 }))
    else:
      var docs = waitfor coll.findAll(sort = bson({ countId: -1 }))
    let dlen = docs.len
    assert dlen == insertDocs.len
    for i in 0 .. docs.high:
      assert docs[i]["countId"] == dlen-i-1

    let limit = 5
    when anoSocketSync:
      docs = coll.findAll(bson(), limit = 5)
    else:
      docs = waitfor coll.findAll(bson(), limit = 5)
    assert docs.len == limit

  block: # &"Find iterate on {namespace}":
    var count = 0
    when anoSocketSync:
      for d in coll.findIter():
        assert d["countId"] == count
        inc count
    else:
      for d in waitfor coll.findIter():
        assert d["countId"] == count
        inc count

  block: # &"Remove countId 1 and 5 on {namespace}":
    let toremove = @[1.toBson, 5]
    when anoSocketSync:
      wr = coll.remove(bson({
        countId: { "$in": toremove },
      }))
    else:
      wr = waitfor coll.remove(bson({
        countId: { "$in": toremove },
      }))
    assert wr.success
    assert toremove.len == wr.n

  block: # &"FindAndModify countId 8 to be 80 on {namespace}":
    require coll != nil
    let oldcount = 8
    let newcount = 80
    when anoSocketSync:
      let olddoc = coll.findAndModify(query = bson({
        countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    else:
      let olddoc = waitfor coll.findAndModify(query = bson({
        countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    assert olddoc["countId"] == oldcount
    when anoSocketSync:
      let newdoc = coll.findOne(bson({ countId: newcount }))
    else:
      let newdoc = waitFor coll.findOne(bson({ countId: newcount }))
    assert newdoc["countId"] == newcount

  block: # &"Update countId 9 $inc by 90 on {namespace}":
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
    assert wr.success
    assert wr.n == 1
    when anoSocketSync:
      let newdoc = coll.findOne(bson({ countId: oldcount + addcount }))
    else:
      let newdoc = waitFor coll.findOne(bson({ countId: oldcount + addcount }))
    assert newdoc["countId"] == olddoc["countId"] + addcount
    assert newdoc["type"] == newtype
    assert newdoc["addedTime"] == olddoc["addedTime"].ofTime

  block: # &"Drop index collection of {namespace}":
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

  block: # &"Bulk write ordered collection of {namespace}":
    errcatch(MongoError) do:
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
    # assert bulkres.nInserted == 2
    assert bulkres.nRemoved == 1
    assert bulkres.nModified == 2
    assert bulkres.writeErrors.len == 0

    # will error and stop in 2nd ops since it's ordered
    when anoSocketSync:
      let _ = coll.remove(bson({ "_id": 4 }))
      bulkres = coll.bulkWrite(ops)
    else:
      let _ = waitfor coll.remove(bson({ "_id": 4 }))
      bulkres = waitfor coll.bulkWrite(ops)
    assert bulkres.nInserted == 1
    assert bulkres.writeErrors.len == 1

  block: # &"Bulk write unordered collection of {namespace}":
    # clean up from previous input
    when anoSocketSync:
      discard coll.remove(bson({
        "char": { "$ne": bsonNull() }
      }))
      assert coll.count() == 8
      discard coll.insert(newdocs)
      var bulkres = coll.bulkWrite(ops, ordered = false)
    else:
      discard waitfor coll.remove(bson({
        "char": { "$ne": bsonNull() }
      }))
      assert (waitfor coll.count()) == 8
      discard waitfor coll.insert(newdocs)
      var bulkres = waitfor coll.bulkWrite(ops, ordered = false)
    assert bulkres.nInserted == 2
    assert bulkres.nRemoved == 1
    assert bulkres.nModified == 2
    assert bulkres.writeErrors.len == 0

    # will give error at 2nd op but continue with other ops because ordered false
    when anoSocketSync:
      discard coll.remove(bson({
        "char": { "$ne": bsonNull() }
      }))
      assert coll.count() == 8
      discard coll.insert(newdocs)
      discard coll.insert(@[bson({ "_id": 5, "char": "Taeln", "class": "fighter", "lvl": 3 })])
      bulkres = coll.bulkWrite(ops, ordered = false)
    else:
      discard waitfor coll.remove(bson({
        "char": { "$ne": bsonNull() }
      }))
      assert (waitfor coll.count()) == 8
      discard waitfor coll.insert(newdocs)
      discard waitfor coll.insert(@[bson({ "_id": 5, "char": "Taeln", "class": "fighter", "lvl": 3 })])
      bulkres = waitfor coll.bulkWrite(ops, ordered = false)
    assert bulkres.nInserted == 1
    assert bulkres.nRemoved == 1
    assert bulkres.nModified == 2
    assert bulkres.writeErrors.len == 1

  block: # &"Drop collection {coll.db.name}.{targetColl}":
    require coll != nil
    when anoSocketSync:
      wr = coll.drop
    else:
      wr = waitFor coll.drop
    wr.success.reasonedCheck("collections.drop error", wr.reason)

  block: # &"Drop database {coll.db.name}":
    require coll != nil
    when anoSocketSync:
      wr = coll.db.dropDatabase
    else:
      wr = waitFor coll.db.dropDatabase
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