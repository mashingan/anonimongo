import std/[asyncdispatch, tables, deques, strformat, sequtils]
from std/strutils import parseEnum
import os, net

import ../core/[types, wire, bson, pool, utils]
import multisock

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
when not defined(anostreamable):
  const anonimongoVersion* = "0.7.1"
else:
  const anonimongoVersion* = "0.7.1-stream"

proc handshake(m: Mongo[AsyncSocket], isMaster: bool, s: AsyncSocket, db: string, id: int32,
  appname = "Anonimongo client apps"):Future[ReplyFormat] {.multisock.} =
  let appname = appname
  let master = if isMaster: 1 else: 0
  var q = bson({
    isMaster: master,
    client: {
      application: { name: appname },
      driver: {
        name: drivername & " - " & description,
        version: anonimongoVersion,
      },
      os: {
        "type": hostOS,
        architecture: hostCPU,
      }
    }
  })
  let compressions = m.compressions
  if compressions.len > 0:
    q["compression"] = compressions.mapIt(($it).toBson)
  when verbose:
    echo "Handshake id: ", id
    dump compressions
    dump q
  var db = db
  let dbc = m[move db]
  result = await sendops(q, dbc, cmd = ckWrite)
  when verbose:
    look result

proc connectEach(m: Mongo[AsyncSocket]): Future[bool] {.async.} =
  try:
    var connectops = newseq[Future[void]]()
    for _, server in m.servers:
      connectops.add server.pool.connect(server.host, server.port.int)
    await all(connectops)
  except CatchableError:
    echo getCurrentExceptionMsg()
    result = false
    return
  result = true

proc connectEach(m: Mongo[Socket]): bool =
  try:
    for _, server in m.servers:
      server.pool.connect(server.host, server.port.int)
  except CatchableError:
    echo getCurrentExceptionMsg()
    result = false
    return
  result = true

proc handshakeEach(m: Mongo[AsyncSocket], dbname, appname: string): Future[seq[ReplyFormat]] {.async.} =
  var ops = newseq[Future[ReplyFormat]](m.main.pool.available.len)
  for id, c in m.main.pool.connections:
    ops[id-1] = m.handshake(m.main.isMaster, c.socket, dbname, id.int32, appname)
  result = await all(ops)

proc handshakeEach(m: Mongo[Socket], dbname, appname: string): seq[ReplyFormat] =
  for id, c in m.main.pool.connections:
    result.add m.handshake(m.main.isMaster, c.socket, dbname, id.int32, appname)

proc connect*(m: Mongo[AsyncSocket]): Future[bool] {.multisock.} =
  result = await m.connectEach
  if not result: return
  result = true
  let appname =
    if "appname" in m.query and m.query["appname"].len > 0:
      m.query["appname"][0]
    else: "Anonimongo client apps"
  let dbname = if m.db != "": m.db else: "admin"
  let replies = await m.handshakeEach(dbname, appname)
  type HandshakeTemp = object
    hosts*: seq[string]
    primary*: string
  if replies.len > 0 and replies[0].numberReturned > 0:
    let b = replies[0].documents[0]
    if b.ok:
      let hktemp = replies[0].documents[0].to HandshakeTemp
      m.hosts = hktemp.hosts
      m.primary = hktemp.primary
      if m.hosts.len <= 1: m.retryableWrites = false
      var serverCompressions =
        if "compression" in b: b["compression"].ofArray.mapIt(
          it.ofString.parseEnum[:CompressorId])
        else: @[]
      when verbose: echo "Server support compressions: ", serverCompressions
      m.compressions = serverCompressions

proc cuUsers(db: Database[AsyncSocket], query: BsonDocument):
  Future[WriteResult] {.multisock.} =
  let dbname = if db.name != "": db.name else: "admin"
  result = await db.proceed(query, dbname, needCompress = false)

template dropPrologue(db: Database[Multisock], qfield, val: untyped): untyped =
  var dbname = db.name & ".$cmd"
  var q = bson({`qfield`: `val`})
  if not db.db.writeConcern.isNil:
    q["writeConcern"] = db.db.writeConcern
  (move dbname, q)

template cuPrep(db: Database[Multisock], field, val, pwd: string,
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

proc createUser*(db: Database[AsyncSocket], user, pwd: string, roles = bsonArray(),
    restrictions = bsonArray(),
    mechanism = bsonArray("SCRAM-SHA-256", "SCRAM-SHA-1"),
    writeConcern = bsonNull(),
    customData = bsonNull()): Future[WriteResult] {.multisock.} =
  let q = cuPrep(db, "createUser", user, pwd, roles, restrictions,
    mechanism, writeConcern, customData)
  result = await cuUsers(db, q)

proc updateUser*(db: Database[AsyncSocket], user, pwd: string, roles = bsonArray(),
    restrictions = bsonArray(),
    mechanism = bsonArray("SCRAM-SHA-256", "SCRAM-SHA-1"),
    writeConcern = bsonNull(),
    customData = bsonNull()): Future[WriteResult] {.multisock.} =
  let q = cuPrep(db, "updateUser", user, pwd, roles, restrictions,
    mechanism, writeConcern, customData)
  result = await cuUsers(db, q)

proc usersInfo*(db: Database[AsyncSocket], usersInfo: BsonBase, showCredentials = false,
  showPrivileges = false, showAuthenticationRestictions = false,
  filters = bson(), comment = bsonNull()): Future[BsonDocument]{.multisock.} =
  var q = bson {
    usersInfo: usersInfo
  }
  for _, (k, v) in [("showCredentials", showCredentials),
    ("showPrivileges", showPrivileges),
    ("showAuthenticationRestictions", showAuthenticationRestictions)]:
    if v: q[k] = v
  if not filters.isNil:
    q["filters"] = filters
  if not comment.isNil:
    q["comment"] = comment
  result = await db.crudops(q, cmd = ckRead)

proc dropAllUsersFromDatabase*(db: Database[AsyncSocket]): Future[WriteResult] {.multisock.} =
  let (_, q) = dropPrologue(db, dropAllUsersFromDatabase, 1)
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  let reply = await sendops(q, db, cmd = ckWrite, compression = compression)
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
  result.n = stat["n"]

proc dropUser*(db: Database[AsyncSocket], user: string): Future[WriteResult] {.multisock.} =
  let (_, q) = dropPrologue(db, dropUser, user)
  result = await db.proceed(q)

template grantOrRevoke(db: Database[Multisock], op: untyped, user: string,
  roles, writeConcern: BsonBase): untyped =
  var q = bson({
    `op`: user,
    roles: roles,
  })
  q.addWriteConcern(db, writeConcern)
  q

proc grantRolesToUser*(db: Database[AsyncSocket], user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[WriteResult] {.multisock.} =
  result = await db.proceed(grantOrRevoke(db, grantRolesToUser, user, roles, writeConcern))

proc revokeRolesFromUser*(db: Database[AsyncSocket], user: string, roles = bsonArray(),
  writeConcern = bsonNull()): Future[WriteResult] {.multisock.} =
  result = await db.proceed(grantOrRevoke(db, revokeRolesFromUser, user, roles, writeConcern))
