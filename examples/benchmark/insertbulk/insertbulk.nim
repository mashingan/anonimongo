from std/sugar import dump
import std/times
import benchy
import anonimongo

dump anonimongoVersion
const maxiter = 10_000
var bsonbody = newseq[BsonDocument](maxiter)
const isekai = "hello異世界"
let
  currtime = getTime()
  ## add import std/oids if we want to supply object id
  # curroid = genOid()

for i in 0 .. bsonbody.high:
    var b = bson {
        hello: i,
        "hello world": isekai,
        "a percent of truth": 0.42,
        "array world": ["red", 50, 4.2],
        "this is null": nil,
        now: currtime,
        # "_id": curroid
    }
    bsonbody[i] = move b

let mongo = newMongo()
if not waitfor mongo.connect:
    quit "cannot connect, quit"
let
    db = mongo["newtemptest"]
    coll = db["temptest"]

dump waitfor coll.drop

timeIt "insert bulk":
    # for _ in 1 .. 100:
        let r = waitfor coll.insert(bsonbody)
        discard waitfor coll.drop()
        keep(r)

#dump waitfor(db.dropDatabase())
close mongo