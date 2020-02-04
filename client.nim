import asyncdispatch, tables, deques, strformat
import os, net
when not defined(release):
  import sugar

import types, wire, bson, pool

const
  drivername = "anonimongo"
  description = "nim mongo driver"
  version = "0.1.0"

proc handshake(m: Mongo, s: AsyncSocket, db: string, id: int32,
  appname = "Anonimongo client apps") {.async.} =
  let appname = appname
  let master = if m.isMaster: 1 else: 0
  let q = bson({
    isMaster: master,
    client: {
      application: { name: appname },
      driver: {
        name: drivername & " - " & description,
        version: version,
      },
      os: {
        "type": hostOS,
        architecture: hostCPU,
      }
    }
  })
  when not defined(release):
    echo "Handshake id: ", id
    dump q
  var stream = newStringStream()
  discard stream.prepareQuery(id, 0, opQuery.int32, 0, db,
    0, 1, q)
  await s.send stream.readAll
  when not defined(release):
    look(await s.getReply)
  else:
    discard await s.getReply

proc connect*(m: Mongo): Future[bool] {.async.} =
  try:
    await(m.pool.connect(m.host, m.port.int))
  except:
    echo getCurrentExceptionMsg()
    return
  result = true
  let appname =
    if "appname" in m.query and m.query["appname"].len > 0:
      m.query["appname"][0]
    else: "Anonimongo client apps"
  var ops = newSeqOfCap[Future[void]](m.pool.available.len)
  let dbname = if m.db != "": (m.db & "$.cmd") else: "admin.$cmd"
  for id, c in m.pool.connections:
    ops.add m.handshake(c.socket, dbname, id.int32, appname)
  await all(ops)
  result = true

proc `[]`*(m: Mongo, name: string): Database =
  result.db = m
  result.name = name

proc `[]`*(dbase: Database, name: string): Collection =
  result.name = name
  result.db = dbase.db

proc createUser*(db: Mongo | Database, query: BsonDocument):
  Future[(bool, string)] {.async.} =
  when db is Database:
    let mdb = db.db
    let pool = db.db.pool
  else:
    let mdb = db
    let pool = db.pool
  let dbname = if mdb.db == "": "admin.$cmd" else: mdb.db & ".$cmd"
  let (id, conn) = await pool.getConn()
  var s = prepare(q, dbname)
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  try:
    pool.endConn id
  except IndexError:
    # because of deque bug with index-bound check
    echo getCurrentExceptionMsg()
    pool.available.addFirst id
  let (success, reason) = check reply
  if not success:
    result[1] = reason
    return
  let res = reply.documents[0]
  if not res.ok:
    result[1] = res.errMsg
    return
  result[0] = true

template dropPrologue(db: Database, qfield, val: untyped): untyped =
  let dbname = db.name & "$.cmd"
  var q = bson({`qfield`: `val`})
  if not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern
  (dbname, q)

template tryEnd(p: Pool, id: int) =
  try:
    p.endConn id
  except IndexError:
    echo getCurrentExceptionMsg()
    p.available.addFirst id


proc dropAllUsersFromDatabase*(db: Database): Future[(bool, int)] {.async.} =
  let (dbname, q) = dropPrologue(db, dropAllUsersFromDatabase, 1)
  var s = prepare(q, dbname)
  let (id, conn) = await db.db.pool.getConn
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  tryEnd(db.db.pool, id)
  let (success, reason) = check reply
  if not success:
    echo reason
    return
  let stat = reply.documents[0]
  if not stat.ok:
    echo stat.errMsg
    return
  result = (true, stat["n"].get.ofInt)

proc dropUser*(db: Database, user: string): Future[(bool, string)] {.async.} =
  let (dbname, q) = dropPrologue(db, dropUser, user)
  var s = prepare(q, dbname)
  let (id, conn) = await db.db.pool.getConn
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  tryEnd(db.db.pool, id)
  let (success, reason) = check reply
  if not success:
    result[1] = reason
    return
  let stat = reply.documents[0]
  if not stat.ok:
    result[1] = stat.errMsg
    return
  result = (true, "")

when isMainModule:
  when defined(ssl):
    const key {.strdefine.} = "d:/dev/self-signed-cert/key.pem"
    const cert {.strdefine.} = "d:/dev/self-signed-cert/cert.pem"
    let sslinfo = initSSLInfo(key, cert)
  else:
    let sslinfo = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  let mongo = newMongo(poolconn = 2, sslinfo = sslinfo)
  echo &"is mongo authenticated: {mongo.authenticated}"
  mongo.appname = "Test driver"
  echo &"now mongo app name is {mongo.appname}"
  if not waitFor mongo.connect:
    echo "error connecting, quit"
  echo &"current available conns: {mongo.pool.available.len}"
  sleep 5000
  mongo.pool.close