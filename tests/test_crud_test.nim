import unittest, os, osproc, times, strformat, sequtils
import sugar

import testutils
import anonimongo

{.warning[UnusedImport]: off.}

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "CRUD tests":
  test "Mongo server is running":
    if runlocal:
      require mongorun.running
    else:
      check true

  var
    mongo: Mongo
    db: Database
    insertDocs = newseq[BsonDocument](10)
    testdb = "newtemptest"
    collname = "temptestcoll"
    foundDocs = newseq[BsonDocument]()
    namespace = ""
    resfind: BsonDocument
    wr: WriteResult

  let currtime = now().toTime
  for i in 0 ..< 10:
    insertDocs[i] = bson({
        countId: i,
        addedTime: currtime + initDuration(minutes = i * 10),
        `type`: "insertTest",
    })
  
  test "Mongo connected and authenticated":
    mongo = testsetup()
    require mongo.authenticated
    db = mongo[testdb]
    namespace = &"{db.name}.{collname}"

  test &"Find documents on {namespace}":
    # find all documents
    require db != nil
    resfind = waitfor db.find(collname)
    resfind.reasonedCheck "find error"
    check resfind["cursor"]["firstBatch"].ofArray.len == 0
    resfind = waitFor db.find(collname, bson(), batchSize = 1,
      singleBatch = true)
    resfind.reasonedCheck "find error"
    check resfind["cursor"]["id"] == 0

  test &"Insert documents on {namespace}":
    require db != nil
    resfind = waitfor db.insert(collname, insertDocs)
    resfind.reasonedCheck "Insert documents error"
    check resfind["n"] == insertDocs.len
    resfind = waitfor db.find(collname, singleBatch = true)
    check resfind.ok
    for d in resfind["cursor"]["firstBatch"].ofArray:
      foundDocs.add d
    check foundDocs.len == insertDocs.len

  test &"Count documents on {namespace}":
    require db != nil
    resfind = waitfor db.count(collname)
    resfind.reasonedCheck("count error")
    check resfind["n"] == foundDocs.len

  test &"Aggregate documents on {namespace}":
    require db != nil
    let tensOfMinutes = 5
    let lesstime = currtime + initDuration(minutes = tensOfMinutes * 10)
    let pipeline = @[
      bson({ "$match": { addedTime: { "$gte": currtime, "$lt": lesstime }}}),
      bson({ "$project": {
        addedTime: { "$dateToString": {
          date: "$addedTime",
          format: "%G-%m-%dT-%H-%M-%S%z",
          timezone: "+07:00", }}}})
    ]
    resfind = waitfor db.aggregate(collname, pipeline)
    resfind.reasonedCheck("db.aggregate error")
    let doc = resfind["cursor"]["firstBatch"].ofArray
    check doc.len == tensOfMinutes

  test &"Distinct documents on {namespace}":
    require db != nil
    resfind = waitfor db.`distinct`(collname, "countId")
    resfind.reasonedCheck "db.distinct error"
    let docs = resfind["values"].ofArray
    check docs.len == insertDocs.len
    check docs.allIt( it.kind == bkInt32 )
  
  test &"Find and modify some document(s) on {namespace}":
    require db != nil
    let newcount = 80
    let oldcount = 8
    resfind = waitfor db.findAndModify(collname, query = bson({
      countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    resfind.reasonedCheck "findAndModify error"
    check resfind["lastErrorObject"]["n"] == 1
    let olddoc = resfind["value"].ofEmbedded

    # let's see we cannot find the old entry
    resfind = waitFor db.find(collname, bson({ countId: oldcount}),
      singleBatch = true)
    resfind.reasonedCheck "find error"
    check resfind["cursor"]["id"] == 0
    var docs = resfind["cursor"]["firstBatch"].ofArray
    #let docs = resfind["cursor"]["firstBatch"].ofArray
    check docs.len == 0

    resfind = waitFor db.find(collname, bson({ countId: newcount}),
      singleBatch = true)
    resfind.reasonedCheck "find error"
    docs = resfind["cursor"]["firstBatch"].ofArray
    let foundDoc = docs[0].ofEmbedded
    check foundDoc["countId"].ofInt != olddoc["countId"]
    check foundDoc["type"].ofString == olddoc["type"]
    check foundDoc["addedTime"] == olddoc["addedTime"].ofTime
    check foundDoc["countId"] == newcount

  test &"Update document(s) on {namespace}":
    require db != nil
    let addcount = 90
    let oldcount = 9
    let newtype = "異世界召喚"
    resfind = waitFor db.find(collname, bson({ countId: oldcount }))
    resfind.reasonedCheck "find error"
    let olddoc = resfind["cursor"]["firstBatch"][0].ofEmbedded
    resfind = waitfor db.update(collname, @[
      bson({
        q: { countId: oldcount },
        u: { "$set": { "type": newtype }, "$inc": { countId: addcount }},
        upsert: false,
        multi: true,
      })
    ])
    resfind.reasonedCheck "update error"
    check resfind["n"] == 1
    check resfind["nModified"] == 1
    resfind = waitFor db.find(collname, bson({ countId: oldcount + addcount }))
    resfind.reasonedCheck "find error"
    let docs = resfind["cursor"]["firstBatch"].ofArray
    check docs.len == 1
    let newdoc = docs[0].ofEmbedded
    check newdoc["countId"] == olddoc["countId"] + addcount
    check newdoc["type"] == newtype
    check newdoc["addedTime"] == olddoc["addedTime"].ofTime

  test &"Find with lazyily on {namespace}":
    require db != nil
    resfind = waitFor db.find(collname, batchSize = 1)
    resfind.reasonedCheck "find error"
    var cursor = (resfind["cursor"].ofEmbedded).to Cursor
    var count = cursor.firstBatch.len
    while true:
      resfind = waitfor db.getMore(cursor.id, collname, 1)
      cursor = (resfind["cursor"].ofEmbedded).to Cursor
      if cursor.nextBatch.len == 0:
        break
      if not (count == 8 or count == 9):
        # it's inserted from 0
        check cursor.nextBatch[0]["countId"] == count
      else:
        let curcount = cursor.nextBatch[0]["countId"].ofInt
        check(curcount == 80 or curcount == 99)
      inc count
    check count == foundDocs.len

  test &"Delete document(s) on {namespace}":
    require db != nil
    var todelete = "insertTest"
    resfind = waitfor db.delete(collname, @[
      bson({ q: {
        "type": todelete,
      }, limit: 0, collation: {
        locale: "en_US_POSIX",
        caseLevel: false,
      }})
    ])
    resfind.reasonedCheck "find error"
    check resfind["n"] == foundDocs.len-1 # because of update

  test &"Drop database {db.name}":
    require db != nil
    wr = waitFor db.dropDatabase
    wr.success.reasonedCheck("dropDatabase error", wr.reason)

  test "Shutdown mongo":
    if runlocal:
      require mongo != nil
      wr = waitFor mongo.shutdown(timeout = 10)
      check wr.success
    else:
      skip()

  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo