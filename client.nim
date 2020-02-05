import asyncdispatch, tables, deques, strformat
import os, net, sha1, nimsha2
when not defined(release):
  import sugar

import types, wire, bson, pool

{.warning[UnusedImport]: off.}
{.hint[XDeclaredButNotUsed]: off.}

const dangerBuild = defined(danger)

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
  new result
  result.db = m
  result.name = name

proc `[]`*(dbase: Database, name: string): Collection =
  result.name = name
  result.db = dbase.db

proc epilogueCheck(reply: ReplyFormat, target: var string): bool =
  dump reply
  let (success, reason) = check reply
  if not success:
    target = reason
    return false
  let stat = reply.documents[0]
  if not stat.ok:
    target = stat.errMsg
    return false
  true

template tryEnd(p: Pool, id: int) =
  try:
    p.endConn id
  except RangeError:
    echo getCurrentExceptionMsg()
    #p.available.addFirst id

proc createUser*(db: Database, query: BsonDocument):
  Future[(bool, string)] {.async.} =
  var mdb = db.db
  var pool = mdb.pool
  #let dbname = if mdb.db == "": "admin.$cmd" else: mdb.db & ".$cmd"
  let dbname = if db.name != "": (db.name & ".$cmd") else: "admin.$cmd"
  dump dbname
  dump query
  let (id, conn) = await pool.getConn()
  var s = prepare(query, (mdb.flags as int32), dbname)
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  dump reply
  when not dangerBuild:
    tryEnd(pool, id)
  else:
    pool.endConn(id)
  #epilogueCheck(reply, result[1])
  result[0] = epilogueCheck(reply, result[1])

template dropPrologue(db: Database, qfield, val: untyped): untyped =
  let dbname = db.name & "$.cmd"
  var q = bson({`qfield`: `val`})
  if not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern
  (dbname, q)

proc dropAllUsersFromDatabase*(db: Database): Future[(bool, int)] {.async.} =
  let (dbname, q) = dropPrologue(db, dropAllUsersFromDatabase, 1)
  var s = prepare(q, (db.db.flags as int32), dbname)
  let (id, conn) = await db.db.pool.getConn
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  when not dangerBuild:
    tryEnd(db.db.pool, id)
  else:
    db.db.pool.endConn id
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
  var s = prepare(q, (db.db.flags as int32), dbname)
  #var s = prepare(q, "admin.$cmd")
  let (id, conn) = await db.db.pool.getConn
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  when not dangerBuild:
    tryEnd(db.db.pool, id)
  else:
    db.db.pool.endConn id
  result[0] = epilogueCheck(reply, result[1])

proc grantRolesToUser*(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[(bool, string)] {.async.} =
  let dbname = db.name & "$.cmd"
  #let dbname = "admin.$cmd"
  var q = bson({
    grantRolesToUser: user,
    roles: roles,
  })
  var dbm = db.db
  if not writeConcern.isNil:
    q["writeConcern"] = writeConcern
  elif not dbm.writeConcern.isNil:
    q["writeConcern"] = dbm.writeConcern
  var s = prepare(q, (dbm.flags as int32), dbname)
  let (id, conn) = await dbm.pool.getConn()
  await conn.socket.send s.readAll
  let reply = await conn.socket.getReply
  when not dangerBuild:
    tryEnd(dbm.pool, id)
  else:
    dbm.pool.endConn id
  result[0] = epilogueCheck(reply, result[1])

when isMainModule:
  when defined(ssl):
    const key {.strdefine.} = "d:/dev/self-signed-cert/key.pem"
    const cert {.strdefine.} = "d:/dev/self-signed-cert/cert.pem"
    let sslinfo = initSSLInfo(key, cert)
  else:
    let sslinfo = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  let mongo = newMongo(poolconn = 2, sslinfo = sslinfo)
  mongo.appname = "Test driver"
  echo &"now mongo app name is {mongo.appname}"
  if not waitFor mongo.connect:
    echo "error connecting, quit"
  echo &"current available conns: {mongo.pool.available.len}"
  if not waitFor(authenticate[Sha256Digest](mongo, "rdruffy", "rdruffy")):
  #if not waitFor(authenticate[Sha1Digest](mongo, "rdruffy", "rdruffy")):
    echo "cannot authenticate the connection"
  echo &"is mongo authenticated: {mongo.authenticated}"
  if mongo.authenticated:
    var db = mongo["temptest"]
    var (success, reason) = waitFor db.createUser(bson({
      createUser: "testuser01",
      pwd: "testtest",
      customData: { role: "testing" },
      roles: [
        { role: "readAnyDatabase", db: "admin" },
        "readWrite",
      ],
    }))
    if not success:
      echo "create user not success: ", reason
    else:
      echo "create user success"

    (success, reason) = waitFor db.grantRolesToUser("testuser01",
      roles = bsonArray(bson({role: "dropUser", db: "admin"}).toBson, "dropUser"))
    if not success:
      echo "grant role not success: ", reason
    else:
      echo "grant role success"

    # now deleting the user
    (success, reason) = waitFor db.dropUser("testuser01")
    if not success:
      echo "deleting not success: ", reason
    else:
      echo "dropping user success"
  
  sleep 1000
  mongo.pool.close