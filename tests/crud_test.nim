import unittest, os, osproc, times, strformat
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
    check resfind["n"].get == insertDocs.len
    resfind = waitfor db.find(collname, singleBatch = true)
    check resfind.ok
    for d in resfind["cursor"]["firstBatch"].ofArray:
      foundDocs.add d
    check foundDocs.len == insertDocs.len

  test &"Count documents on {namespace}":
    require db != nil
    resfind = waitfor db.count(collname)
    resfind.reasonedCheck("count error")
    check resfind["n"].get == foundDocs.len
  
  test &"Find and modify some document(s) on {namespace}":
    require db != nil
    let newcount = 80
    let oldcount = 8
    resfind = waitfor db.findAndModify(collname, query = bson({
      countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    resfind.reasonedCheck "findAndModify error"
    check resfind["lastErrorObject"]["n"].get == 1
    let olddoc = resfind["value"].get.ofEmbedded

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
    let foundDoc = docs[0].get.ofEmbedded
    check foundDoc["countId"].get.ofInt != olddoc["countId"].get
    check foundDoc["type"].get.ofString == olddoc["type"].get
    check foundDoc["addedTime"].get == olddoc["addedTime"].get.ofTime
    check foundDoc["countId"].get == newcount

  test &"Update document(s) on {namespace}":
    require db != nil
    let addcount = 90
    let oldcount = 9
    let newtype = "異世界召喚"
    resfind = waitFor db.find(collname, bson({ countId: oldcount }))
    resfind.reasonedCheck "find error"
    let olddoc = resfind["cursor"]["firstBatch"][0].get.ofEmbedded
    resfind = waitfor db.update(collname, @[
      bson({
        q: { countId: oldcount },
        u: { "$set": { "type": newtype }, "$inc": { countId: addcount }},
        upsert: false,
        multi: true,
      })
    ])
    resfind.reasonedCheck "update error"
    check resfind["n"].get == 1
    check resfind["nModified"].get == 1
    resfind = waitFor db.find(collname, bson({ countId: oldcount + addcount }))
    resfind.reasonedCheck "find error"
    let docs = resfind["cursor"]["firstBatch"].ofArray
    check docs.len == 1
    let newdoc = docs[0].ofEmbedded
    check newdoc["countId"].get == olddoc["countId"].get + addcount
    check newdoc["type"].get == newtype
    check newdoc["addedTime"].get == olddoc["addedTime"].get.ofTime

  test &"Find with lazyily on {namespace}":
    require db != nil
    resfind = waitFor db.find(collname, batchSize = 1)
    resfind.reasonedCheck "find error"
    var cursor = (resfind["cursor"].get.ofEmbedded).to Cursor
    var count = cursor.firstBatch.len
    while true:
      resfind = waitfor db.getMore(cursor.id, collname, 1)
      cursor = (resfind["cursor"].get.ofEmbedded).to Cursor
      if cursor.nextBatch.len == 0:
        break
      if not (count == 8 or count == 9):
        # it's inserted from 0
        check cursor.nextBatch[0]["countId"].get == count
      else:
        let curcount = cursor.nextBatch[0]["countId"].get.ofInt
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
    check resfind["n"].get == foundDocs.len-1 # because of update

  test &"Drop database {db.name}":
    require db != nil
    let (success, reason) = waitFor db.dropDatabase
    success.reasonedCheck("dropDatabase error", reason)

  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo