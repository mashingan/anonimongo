import asyncdispatch, tables, deques, strformat
import os, net, sha1, nimsha2
when not defined(release):
  import sugar

import types, wire, bson, pool, utils

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
  let dbc = m[db]
  let reply = await sendops(q, dbc)
  when not defined(release):
    look reply

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
  let dbname = if m.db != "": m.db else: "admin"
  for id, c in m.pool.connections:
    ops.add m.handshake(c.socket, dbname, id.int32, appname)
  await all(ops)
  result = true

proc cuUsers(db: Database, query: BsonDocument):
  Future[(bool, string)] {.async.} =
  let dbname = if db.name != "": db.name else: "admin"
  result = await db.proceed(query, dbname)

template dropPrologue(db: Database, qfield, val: untyped): untyped =
  let dbname = db.name & ".$cmd"
  var q = bson({`qfield`: `val`})
  if not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern
  (dbname, q)

template cuPrep(db: Database, field, val, pwd: string,
  roles, restrictions, mechanism: BsonBase,
  writeConcern, customData: BsonBase): untyped =
  var q = bson()
  q[field] = val
  q["pwd"] = pwd
  if not customData.isNil:
    q["customData"] = customData
  q["roles"] = roles
  if field == "createUser":
    if not writeConcern.isNil:
      q["writeConcern"] = writeConcern
    elif not db.db.writeConcern.isNil:
      q["writeConcern"] = db.db.writeConcern
    q["authenticationRestrictions"] = restrictions
    q["mechanisms"] = mechanism
  elif field == "updateUser":
    q["authenticationRestrictions"] = restrictions
    q["mechanisms"] = mechanism
    if not writeConcern.isNil:
      q["writeConcern"] = writeConcern
    elif not db.db.writeConcern.isNil:
      q["writeConcern"] = db.db.writeConcern
  unown(q)

proc createUser*(db: Database, user, pwd: string, roles = bsonArray(),
    restrictions = bsonArray(),
    mechanism = bsonArray("SCRAM-SHA-256", "SCRAM-SHA-1"),
    writeConcern = bsonNull(),
    customData = bsonNull()): Future[(bool, string)] {.async.} =
  let q = cuPrep(db, "createUser", user, pwd, roles, restrictions,
    mechanism, writeConcern, customData)
  result = await cuUsers(db, q)

proc updateUser*(db: Database, user, pwd: string, roles = bsonArray(),
    restrictions = bsonArray(),
    mechanism = bsonArray("SCRAM-SHA-256", "SCRAM-SHA-1"),
    writeConcern = bsonNull(),
    customData = bsonNull()): Future[(bool, string)] {.async.} =
  let q = cuPrep(db, "updateUser", user, pwd, roles, restrictions,
    mechanism, writeConcern, customData)
  result = await cuUsers(db, q)

proc usersInfo*(db: Database, query: BsonDocument): Future[ReplyFormat]{.async.} =
  result = await sendops(query, db)

proc dropAllUsersFromDatabase*(db: Database): Future[(bool, int)] {.async.} =
  let (_, q) = dropPrologue(db, dropAllUsersFromDatabase, 1)
  let reply = await sendops(q, db)
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
  let (_, q) = dropPrologue(db, dropUser, user)
  result = await db.proceed(q)

proc roleOps(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[(bool, string)] {.async.} =
  var q = bson({
    grantRolesToUser: user,
    roles: roles,
  })
  q.addWriteConcern(db, writeConcern)
  result = await db.proceed(q)

proc grantRolesToUser*(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[(bool, string)] {.async.} =
  result = await roleOps(db, user, roles, writeConcern)

proc revokeRolesFromUser*(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[(bool, string)] {.async.} =
  result = await roleOps(db, user, roles, writeConcern)

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
    look waitFor db.usersInfo(bson({
      usersInfo: { user: "rdruffy", db: "admin" },
      #showPrivileges: true,
    }))
    var (success, reason) = waitFor db.createUser("testuser01", "testtest",
      roles = bsonArray("read"), customData = bson({ role: "testing"}))
    if not success:
      echo "create user not success: ", reason
    else:
      echo "create user success"

    look waitFor db.usersInfo(bson({
      usersInfo: "testuser01",
      #showPrivileges: true,
    }))

    (success, reason) = waitFor db.grantRolesToUser("testuser01",
      roles = bsonArray("write"))
    if not success:
      echo "grant role not success: ", reason
    else:
      echo "grant role success"

    look waitFor db.usersInfo(bson({
      usersInfo: "testuser01",
      #showPrivileges: true,
    }))

    (success, reason) = waitFor db.revokeRolesFromUser("testuser01",
      roles = bsonArray("write"))
    if not success:
      echo "revoke role not success: ", reason
    else:
      echo "revoke role success"

    (success, reason) = waitFor db.updateUser("testuser01", "testtest",
      roles = bsonArray("readWrite"))
    if not success:
      echo "update user not success: ", reason
    else:
      echo "update user success, now checking the user"
      look waitFor db.usersInfo(bson({
        usersInfo: "testuser01",
      }))

    # now deleting the user
    (success, reason) = waitFor db.dropUser("testuser01")
    if not success:
      echo "deleting not success: ", reason
    else:
      echo "dropping user success"
  
  mongo.pool.close