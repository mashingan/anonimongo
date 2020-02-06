import wire, bson, types, pool

func cmd*(name: string): string = name & ".$cmd"

func flags*(d: Database): int32 = d.db.flags as int32

proc sendOps*(q: BsonDocument, db: Database, name = ""): Future[ReplyFormat]{.async.} =
  let dbname = if name == "": db.name.cmd else: name.cmd
  var s = prepare(q, db.flags, dbname)
  let (id, conn) = await db.db.pool.getConn()
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  defer: db.db.pool.endConn(id)
  result = unown(reply)

proc addWriteConcern*(q: var BsonDocument, db: Database, wt: BsonBase) =
  if not wt.isNil:
    q["writeConcern"] = wt
  elif not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern

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