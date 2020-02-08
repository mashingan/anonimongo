import wire, bson, types, pool

func cmd*(name: string): string = name & ".$cmd"

func flags*(d: Database): int32 = d.db.flags as int32

proc sendOps*(q: BsonDocument, db: Database, name = ""):
  Future[ReplyFormat]{.async.} =
  let dbname = if name == "": db.name.cmd else: name.cmd
  let (id, conn) = await db.db.pool.getConn()
  defer: db.db.pool.endConn(id)
  var s = prepare(q, db.flags, dbname, id.int32)
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  result = unown(reply)

proc addWriteConcern*(q: var BsonDocument, db: Database, wt: BsonBase) =
  if not wt.isNil:
    q["writeConcern"] = wt
  elif not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern

template addOptional*(q: var BsonDocument, name: string, f: BsonBase) =
  if not f.isNil:
    q[name] = f

template addConditional*(q: var BsonDocument, field: string, val: BsonBase) =
  if val:
    q[field] = val

proc epilogueCheck*(reply: ReplyFormat, target: var string): bool =
  let (success, reason) = check reply
  if not success:
    target = reason
    return false
  let stat = reply.documents[0]
  if not stat.ok:
    target = stat.errMsg
    return false
  true

proc proceed*(db: Database, q: BsonDocument, dbname = ""):
  Future[(bool, string)] {.async.} =
  let reply = await sendops(q, db, dbname)
  result[0] = epilogueCheck(reply, result[1])

#template crudops(db: Database, q: BsonDocument): untyped {.async.} =
proc crudops*(db: Database, q: BsonDocument): Future[BsonDocument]{.async.} =
  let reply = await sendops(q, db)
  let (success, reason) = check reply
  if not success:
    raise newException(MongoError, reason)
  result = reply.documents[0]