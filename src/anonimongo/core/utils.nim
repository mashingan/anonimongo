import wire, bson, types, pool

const verbose {.booldefine.} = false

when verbose:
  import sugar

func cmd*(name: string): string = name & ".$cmd"
  ## Add suffix ".$cmd" to Database name to avoid any typo.

func flags*(d: Database): int32 = d.db.flags as int32
  ## Get Mongo available ``wire.QueryFlags`` as int32 bitfield

proc sendOps*(q: BsonDocument, db: Database, name = ""):
  Future[ReplyFormat]{.async.} =
  ## A helper utility which greatly simplify actual Database command
  ## queries. Any new command implementation usually use this
  ## helper proc.
  let dbname = if name == "": db.name.cmd else: name.cmd
  let (id, conn) = await db.db.pool.getConn()
  defer: db.db.pool.endConn(id)
  var s = prepare(q, db.flags, dbname, id.int32)
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  result = unown(reply)

proc addWriteConcern*(q: var BsonDocument, db: Database, wt: BsonBase) =
  ## Helper that will modify add writeConcern to BsonDocument query based
  ## on writeConcer data given. If it's nil and Mongo.writeConcern also nil,
  ## bypass without adding this field in query.
  if not wt.isNil:
    q["writeConcern"] = wt
  elif not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern

template addOptional*(q: var BsonDocument, name: string, f: BsonBase) =
  ## Add any optional field to query if it's not nil.
  if not f.isNil:
    q[name] = f

template addConditional*(q: var BsonDocument, field: string, val: BsonBase) =
  ## Add any optional boolean field to query if it's true.
  if val:
    q[field] = val

proc epilogueCheck*(reply: ReplyFormat, target: var string): bool =
  ## Helper utility to check and modify string reason if the operation
  ## wasn't success.
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
  Future[WriteResult] {.async.} =
  ## Helper utility that basically utilize another two main operations
  ## ``sendops`` and ``epilogueCheck``.
  let reply = await sendops(q, db, dbname)
  result = WriteResult(kind: wkSingle)
  result.success = epilogueCheck(reply, result.reason)

#template crudops(db: Database, q: BsonDocument): untyped {.async.} =
proc crudops*(db: Database, q: BsonDocument, dbname = ""):
  Future[BsonDocument]{.async.} =
  ## About the same as ``proceed`` but this will return a BsonDocument
  ## compared to ``proceed`` that return ``(bool, string)``.
  let reply = await sendops(q, db, dbname)
  let (success, reason) = check reply
  if not success:
    raise newException(MongoError, reason)
  result = reply.documents[0]

proc getWResult*(b: BsonDocument): WriteResult =
  ## Helper to fetch a WriteResult of kind wkMany.
  result = WriteResult(
    success: b.ok,
    kind: wkMany
  )
  if "nModified" in b:
    result.n = b["nModified"]
  elif "n" in b:
    result.n = b["n"]
  if "writeErrors" in b:
    let errdocs = b["writeErrors"].ofArray
    result.errmsgs = newseq[string](errdocs.len)
    for i, errb in errdocs:
      result.errmsgs[i] = errb.ofEmbedded.errmsg
      when verbose:
        dump result.errmsgs[i]
  when verbose:
    dump result