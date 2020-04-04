import asyncdispatch, tables, deques, strformat, sequtils
import os, net

import ../core/[types, wire, bson, pool, utils]

{.warning[UnusedImport]: off.}

const verbose = defined(verbose)

when verbose:
  import sugar

## Client module and User Management Commands
## ******************************************
##
## This APIs handling connection for Mongo and also implement user management
## APIs which can be referred `here`_. These APIs are for write/update/modify
## and delete operations hence all of these return tuple of bool success
## together string reason or int n affected documents.
##
## All APIs are async.
##
## .. _here: https://docs.mongodb.com/manual/reference/command/nav-user-management/

const
  drivername = "anonimongo"
  description = "nim mongo driver"
  version = "0.2.0"

proc handshake(m: Mongo, s: AsyncSocket, db: string, id: int32,
  appname = "Anonimongo client apps") {.async.} =
  let appname = appname
  let master = if m.isMaster: 1 else: 0
  var q = bson({
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
  #[ TODO: will be enabled later
  if "compressors" in m.query:
    q["compression"] = m.query["compressors"].map toBson
    ]#
  when verbose:
    echo "Handshake id: ", id
    dump q
  var db = db
  let dbc = m[move db]
  when verbose:
    look await sendops(q, dbc)
  else:
    discard await sendops(q, dbc)

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
  var ops = newseq[Future[void]](m.pool.available.len)
  let dbname = if m.db != "": m.db else: "admin"
  for id, c in m.pool.connections:
    ops[id-1] = m.handshake(c.socket, dbname, id.int32, appname)
  await all(ops)

proc cuUsers(db: Database, query: BsonDocument):
  Future[WriteResult] {.async.} =
  let dbname = if db.name != "": db.name else: "admin"
  result = await db.proceed(query, dbname)

template dropPrologue(db: Database, qfield, val: untyped): untyped =
  var dbname = db.name & ".$cmd"
  var q = bson({`qfield`: `val`})
  if not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern
  (move dbname, q)

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
    customData = bsonNull()): Future[WriteResult] {.async.} =
  let q = cuPrep(db, "createUser", user, pwd, roles, restrictions,
    mechanism, writeConcern, customData)
  result = await cuUsers(db, q)

proc updateUser*(db: Database, user, pwd: string, roles = bsonArray(),
    restrictions = bsonArray(),
    mechanism = bsonArray("SCRAM-SHA-256", "SCRAM-SHA-1"),
    writeConcern = bsonNull(),
    customData = bsonNull()): Future[WriteResult] {.async.} =
  let q = cuPrep(db, "updateUser", user, pwd, roles, restrictions,
    mechanism, writeConcern, customData)
  result = await cuUsers(db, q)

proc usersInfo*(db: Database, query: BsonDocument): Future[ReplyFormat]{.async.} =
  result = await sendops(query, db)

proc dropAllUsersFromDatabase*(db: Database): Future[WriteResult] {.async.} =
  let (_, q) = dropPrologue(db, dropAllUsersFromDatabase, 1)
  let reply = await sendops(q, db)
  let (success, reason) = check reply
  result = WriteResult(
    success: success,
    reason: reason,
    kind: wkMany
  )
  if not success:
    when verbose: echo reason
    return
  let stat = reply.documents[0]
  if not stat.ok:
    when verbose: echo stat.errMsg
    result.success = false
    result.reason = stat.errMsg
    return
  #result = (true, stat["n"].ofInt)
  result.n = stat["n"]

proc dropUser*(db: Database, user: string): Future[WriteResult] {.async.} =
  let (_, q) = dropPrologue(db, dropUser, user)
  result = await db.proceed(q)

proc roleOps(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[WriteResult] {.async.} =
  var q = bson({
    grantRolesToUser: user,
    roles: roles,
  })
  q.addWriteConcern(db, writeConcern)
  result = await db.proceed(q)

proc grantRolesToUser*(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[WriteResult] {.async.} =
  result = await roleOps(db, user, roles, writeConcern)

proc revokeRolesFromUser*(db: Database, user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[WriteResult] {.async.} =
  result = await roleOps(db, user, roles, writeConcern)
