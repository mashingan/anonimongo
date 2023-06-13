discard """
  
  action: "run"
  exitcode: 0
  
  # flags with which to run the test, delimited by `;`
  matrix: "-d:anostreamable -d:danger"
"""

from std/osproc import Process, kill, running, close
from std/os import sleep
from std/sequtils import map, allIt
from std/net import Socket
from std/strformat import `&`
from std/times import now, toTime, initDuration, `+`

import ./utils_test
import anonimongo

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

when (NimMajor, NimMinor, NimPatch) >= (1, 6, 4):
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

proc toCursor[S: TheSock|Socket](b: BsonDocument): Cursor[S] =
  Cursor[S](
    id: b["id"],
    firstBatch: if "firstBatch" in b: b["firstBatch"].ofArray.map(ofEmbedded) else: @[],
    nextBatch: if "nextBatch" in b: b["nextBatch"].ofArray.map(ofEmbedded) else: @[],
    ns: b["ns"]
  )

block: # "CRUD tests":
  block: # "Mongo server is running":
    if runlocal:
      require mongorun.running
    else:
      assert true

  var
    mongo: Mongo[TheSock]
    db: Database[TheSock]
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
  
  block: # "Mongo connected and authenticated":
    mongo = testsetup()
    if mongo.withAuth:
      require mongo.authenticated
    db = mongo[testdb]
    namespace = &"{db.name}.{collname}"

  block: # &"Find documents on {namespace}":
    # find all documents
    require db != nil
    when anoSocketSync:
      discard db.dropCollection(collname) # need to cleanup previous documents
      resfind = db.find(collname)
    else:
      discard waitFor db.dropCollection(collname)
      resfind = waitfor db.find(collname)
    resfind.reasonedCheck "find error"
    assert resfind["cursor"]["firstBatch"].ofArray.len == 0,
      &"""expected 0 len, got {resfind["cursor"]["firstBatch"].ofArray.len}"""
    when anoSocketSync:
      resfind = db.find(collname, bson(), batchSize = 1,
        singleBatch = true)
    else:
      resfind = waitFor db.find(collname, bson(), batchSize = 1,
        singleBatch = true)
    resfind.reasonedCheck "find error"
    assert resfind["cursor"]["id"] == 0

  block: # &"Insert documents on {namespace}":
    require db != nil

    # insert twice to check whether stream is reset
    # when used for the 2nd time
    for _ in 1 .. 2:
      when anoSocketSync:
        resfind = db.insert(collname, insertDocs)
      else:
        resfind = waitfor db.insert(collname, insertDocs)
      resfind.reasonedCheck "Insert documents error"
      assert resfind["n"] == insertDocs.len

    # to delete excess insertion
    let todeleteq = block:
      var res = newseq[BsonDocument](insertDocs.len)
      for i, doc in res.mpairs:
        doc = bson {
          q: { countId: insertDocs[i]["countId"] },
          limit: 1,
          collation: {
            locale: "en_US_POSIX",
            caseLevel: false,
          }
        }
      res
    when anoSocketSync:
      resfind = db.delete(collname, todeleteq)
    else:
      resfind = waitfor db.delete(collname, todeleteq)
    resfind.reasonedCheck "find error"
    
    when anoSocketSync:
      resfind = db.find(collname, singleBatch = true)
    else:
      resfind = waitfor db.find(collname, singleBatch = true)
    assert resfind.ok
    for d in resfind["cursor"]["firstBatch"].ofArray:
      foundDocs.add d
    assert foundDocs.len == insertDocs.len

  block: # &"Count documents on {namespace}":
    require db != nil
    when anoSocketSync:
      resfind = db.count(collname)
    else:
      resfind = waitfor db.count(collname)
    resfind.reasonedCheck("count error")
    assert resfind["n"] == foundDocs.len

  block: # &"Aggregate documents on {namespace}":
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
    when anoSocketSync:
      resfind = db.aggregate(collname, pipeline)
    else:
      resfind = waitfor db.aggregate(collname, pipeline)
    resfind.reasonedCheck("db.aggregate error")
    let doc = resfind["cursor"]["firstBatch"].ofArray
    assert doc.len == tensOfMinutes

  block: # &"Distinct documents on {namespace}":
    require db != nil
    when anoSocketSync:
      resfind = db.`distinct`(collname, "countId")
    else:
      resfind = waitfor db.`distinct`(collname, "countId")
    resfind.reasonedCheck "db.distinct error"
    let docs = resfind["values"].ofArray
    assert docs.len == insertDocs.len
    assert docs.allIt( it.kind == bkInt32 )
  
  block: # &"Find and modify some document(s) on {namespace}":
    require db != nil
    let newcount = 80
    let oldcount = 8
    when anoSocketSync:
      resfind = db.findAndModify(collname, query = bson({
        countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    else:
      resfind = waitfor db.findAndModify(collname, query = bson({
        countId: oldcount }), update = bson({ "$set": { countId: newcount }}))
    resfind.reasonedCheck "findAndModify error"
    assert resfind["lastErrorObject"]["n"] == 1
    let olddoc = resfind["value"].ofEmbedded

    # let's see we cannot find the old entry
    when anoSocketSync:
      resfind = db.find(collname, bson({ countId: oldcount}),
        singleBatch = true)
    else:
      resfind = waitFor db.find(collname, bson({ countId: oldcount}),
        singleBatch = true)
    resfind.reasonedCheck "find error"
    assert resfind["cursor"]["id"] == 0
    var docs = resfind["cursor"]["firstBatch"].ofArray
    assert docs.len == 0

    when anoSocketSync:
      resfind = db.find(collname, bson({ countId: newcount}),
        singleBatch = true)
    else:
      resfind = waitFor db.find(collname, bson({ countId: newcount}),
        singleBatch = true)
    resfind.reasonedCheck "find error"
    docs = resfind["cursor"]["firstBatch"].ofArray
    let foundDoc = docs[0].ofEmbedded
    assert foundDoc["countId"].ofInt != olddoc["countId"]
    assert foundDoc["type"].ofString == olddoc["type"]
    assert foundDoc["addedTime"] == olddoc["addedTime"].ofTime
    assert foundDoc["countId"] == newcount

  block: # &"Update document(s) on {namespace}":
    require db != nil
    let addcount = 90
    let oldcount = 9
    let newtype = "異世界召喚"
    when anoSocketSync:
      resfind = db.find(collname, bson({ countId: oldcount }))
    else:
      resfind = waitFor db.find(collname, bson({ countId: oldcount }))
    resfind.reasonedCheck "find error"
    let olddoc = resfind["cursor"]["firstBatch"][0].ofEmbedded
    when anoSocketSync:
      resfind = db.update(collname, @[
        bson({
          q: { countId: oldcount },
          u: { "$set": { "type": newtype }, "$inc": { countId: addcount }},
          upsert: false,
          multi: true,
        })
      ])
    else:
      resfind = waitfor db.update(collname, @[
        bson({
          q: { countId: oldcount },
          u: { "$set": { "type": newtype }, "$inc": { countId: addcount }},
          upsert: false,
          multi: true,
        })
      ])
    resfind.reasonedCheck "update error"
    assert resfind["n"] == 1
    assert resfind["nModified"] == 1
    when anoSocketSync:
      resfind = db.find(collname, bson({ countId: oldcount + addcount }))
    else:
      resfind = waitFor db.find(collname, bson({ countId: oldcount + addcount }))
    resfind.reasonedCheck "find error"
    let docs = resfind["cursor"]["firstBatch"].ofArray
    assert docs.len == 1
    let newdoc = docs[0].ofEmbedded
    assert newdoc["countId"] == olddoc["countId"] + addcount
    assert newdoc["type"] == newtype
    assert newdoc["addedTime"] == olddoc["addedTime"].ofTime

  block: # &"Find with lazyily on {namespace}":
    require db != nil
    when anoSocketSync:
      resfind = db.find(collname, batchSize = 1)
    else:
      resfind = waitFor db.find(collname, batchSize = 1)
    resfind.reasonedCheck "find error"
    # var cursor = (resfind["cursor"].ofEmbedded).to Cursor
    var cursor = resfind["cursor"].ofEmbedded.toCursor[:TheSock]
    var count = cursor.firstBatch.len
    while true:
      when anoSocketSync:
        resfind = db.getMore(cursor.id, collname, 1)
      else:
        resfind = waitfor db.getMore(cursor.id, collname, 1)
      cursor = resfind["cursor"].ofEmbedded.toCursor[:TheSock]
      if cursor.nextBatch.len == 0:
        break
      if not (count == 8 or count == 9):
        # it's inserted from 0
        assert cursor.nextBatch[0]["countId"] == count
      else:
        let curcount = cursor.nextBatch[0]["countId"].ofInt
        assert curcount == 80 or curcount == 99
      inc count
    assert count == foundDocs.len

  block: # &"Delete document(s) on {namespace}":
    require db != nil
    var todelete = "insertTest"
    when anoSocketSync:
      resfind = db.delete(collname, @[
        bson({ q: {
          "type": todelete,
        }, limit: 0, collation: {
          locale: "en_US_POSIX",
          caseLevel: false,
        }})
      ])
    else:
      resfind = waitfor db.delete(collname, @[
        bson({ q: {
          "type": todelete,
        }, limit: 0, collation: {
          locale: "en_US_POSIX",
          caseLevel: false,
        }})
      ])
    resfind.reasonedCheck "find error"
    assert resfind["n"] == foundDocs.len-1 # because of update

  block: # &"Drop database {db.name}":
    require db != nil
    when anoSocketSync:
      wr = db.dropDatabase
    else:
      wr = waitFor db.dropDatabase
    wr.success.reasonedCheck("dropDatabase error", wr.reason)

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

  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo