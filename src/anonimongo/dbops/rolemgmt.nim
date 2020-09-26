import sequtils
import ../core/[bson, types, wire, utils]

## Role Management Methods
## ***********************
##
## This APIs can be referred `here`_. All these APIs are returning various
## values accordingly whether it's reading operations or writing operations.
##
## **Beware**: These APIs are not tested.
##
## All APIs are async.
##
## .. _here: https://docs.mongodb.com/manual/reference/method/js-role-management/
## __ here_

proc createRole*(db: Database, name: string, privileges, roles: seq[BsonDocument],
  authRestrict: seq[BsonDocument] = @[], wt = bsonNull()):
  Future[WriteResult]{.async.} =
  var q = !>{
    createRole: name,
    privileges: privileges.map toBson,
    roles: roles.map toBson,
  }
  if authRestrict.len >= 0:
    q["authenticationRestriction"] = authRestrict.map toBson
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, "admin")

proc updateRole*(db: Database, name: string,
  privileges: seq[BsonDocument] = @[],
  roles: seq[BsonDocument] = @[],
  authRestrict: seq[BsonDocument] = @[], wt = bsonNull()):
  Future[WriteResult]{.async.} =
  let privlen = privileges.len
  let rolelen = roles.len
  if privlen == 0 and rolelen == 0:
    result.reason = "Both privileges and roles cannot be empty."
    return
  var q = !>{
    updateRole: name,
  }
  if privlen > 0:
    q["privileges"] = privileges.map toBson
  if rolelen > 0:
    q["roles"] = roles.map toBson
  if authRestrict.len > 0:
    q["authenticationRestriction"] = authRestrict.map toBson
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, "admin")

proc dropRole*(db: Database, role: string, wt = bsonNull()):
  Future[WriteResult]{.async.} =
  var q = !>{ dropRole: role }
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc dropAllRolesFromDatabase*(db: Database, wt = bsonNull()):
    Future[WriteResult] {.async.} =
  var q = !>{ dropAllRolesFromDatabase: 1 }
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

template grantRevoke(db: Database, grname, val, privrole: string,
  wt: BsonBase, prval: untyped): untyped =
  var q = bson()
  q[grname] = val
  q[privrole] = `prval`.map toBson
  q.addWriteConcern(db, wt)
  unown(q)

proc grantPrivilegesToRole*(db: Database, role: string, privileges: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.async.} =
  let q = db.grantRevoke("grantPrivileges", role, "privileges", wt, privileges)
  result = await db.proceed(q)

proc grantRolesToRole*(db: Database, role: string, roles: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.async.} =
  let q = db.grantRevoke("grantRolesToRole", role, "roles", wt, roles)
  result = await db.proceed(q)

proc invalidateUserCache*(db: Database): Future[WriteResult] {.async.} =
  result = await db.proceed(!>{ invalidateUserCache: 1 })

proc revokePrivilegesFromRole*(db: Database, role: string, privileges: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.async.} =
  let q = db.grantRevoke("revokePrivilegesFromRole", role, "privileges", wt, privileges)
  result = await db.proceed(q)

proc revokeRolesFromRole*(db: Database, role: string, roles: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.async.} =
  let q = db.grantRevoke("revokeRolesFromRole", role, "roles", wt, roles)
  result = await db.proceed(q)

proc rolesInfo*(db: Database, info: BsonBase, showPriv = false,
  showBuiltin = false): Future[ReplyFormat] {.async.} =
  let q = !>{
    rolesInfo: info,
    showPrivileges: showPriv,
    showBuiltinRoles: showBuiltin,
  }
  result = await sendops(q, db, cmd = ckRead)