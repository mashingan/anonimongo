from std/sugar import dump
import std/times
import benchy
import anonimongo

dump anonimongoVersion
const
  isekai = "hello異世界"
  insertnum = 100
let
  currtime = getTime()
  ## add import std/oids if we want to supply object id
  # curroid = genOid()

let mongo = newMongo()
if not waitfor mongo.connect:
    quit "cannot connect, quit"
let
    db = mongo["newtemptest"]
    coll = db["temptest"]

dump waitfor coll.drop

var
  o: BsonDocument
  ops = newseq[Future[WriteResult]](insertnum)
timeIt "insert bulk":
  for i in 0 ..< insertnum:
    ops[i] = coll.insert(@[bson {
      oneHundred: i,
      "hello world": isekai,
      "a percent of truth": 0.42,
      "array world": ["red", 50, 4.2],
      "this is null": nil,
      now: currtime,
      # "_id": curroid
    }])
  discard waitfor all ops
  o = waitfor coll.findOne(bson { oneHundred: insertnum-1 })
  keep(o)

dump o
#dump waitfor(db.dropDatabase())
close mongo