import unittest, os, osproc, times, strformat

import types, testutils, bson

const localhost = testutils.host == "localhost"

var mongorun: Process
if localhost:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "CRUD tests":
  test "Mongo server is running":
    if localhost:
      require mongorun.running
    else:
      check true

  var
    mongo: Mongo
    db: Database
    insertDocs = newseq[BsonDocument](10)
    testdb = "newtemptest"
    collname = "temptestcoll"
    foundDocs: seq[BsonDocument]

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

  var namespace = &"{db.name}.{collname}"
  test &"Find documents on {namespace}":
    skip()

  test &"Insert documents on {namespace}":
    skip()

  test &"Update document(s) on {namespace}":
    skip()

  test &"Find with lazyily on {namespace}":
    skip()

  test &"Delete document(s) on {namespace}":
    skip()

  if localhost:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo

#[
    dump insertingdocs
    try:
      var resfind = waitfor db.find("role", bson())
      dump resfind 
      resfind = waitfor db.insert("role", insertingdocs)
      dump resfind
      resfind = waitfor db.find("role", bson())
      dump resfind
      resfind = waitFor db.find("role", bson(), batchSize = 1, singleBatch = true)
      dump resfind
      resfind = waitFor db.find("role", bson(), batchSize = 1)
      dump resfind
      var cur = (resfind["cursor"].get.ofEmbedded).to Cursor
      dump cur
      resfind = waitfor db.findAndModify("role", query = bson({
        countId: 8 }), update = bson({ "$set": { countId: 80 }}))
      dump resfind
      resfind = waitfor db.update("role", @[
        bson({
          q: { countId: 9 },
          u: { "$set": { "type": "異世界召喚" }, "$inc": { countId: 90 }},
          upsert: false,
          multi: true,
        })
      ])
      while true:
        resfind = waitfor db.getMore(cur.id, "role", 1)
        cur = (resfind["cursor"].get.ofEmbedded).to Cursor
        dump cur
        if cur.nextBatch.len == 0:
          break
      resfind = waitfor db.delete("role", @[
        bson({ q: {
          "type": "insertTest",
        }, limit: 0, collation: {
          locale: "en_US_POSIX",
          caseLevel: false,
        }})
      ])
      dump resfind
    except MongoError, UnpackError:
      echo getCurrentExceptionMsg()
    #discard waitFor mongo.shutdown(timeout = 10)
    close mongo.pool
    ]#