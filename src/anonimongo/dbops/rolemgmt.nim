import sequtils
import ../core/[bson, types, wire, utils, multisock]

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

proc createRole*(db: Database[AsyncSocket], name: string, privileges, roles: seq[BsonDocument],
  authRestrict: seq[BsonDocument] = @[], wt = bsonNull()):
  Future[WriteResult]{.multisock.} =
  var q = bson({
    createRole: name,
    privileges: privileges.map toBson,
    roles: roles.map toBson,
  })
  if authRestrict.len >= 0:
    q["authenticationRestriction"] = authRestrict.map toBson
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, "admin")

proc updateRole*(db: Database[AsyncSocket], name: string,
  privileges: seq[BsonDocument] = @[],
  roles: seq[BsonDocument] = @[],
  authRestrict: seq[BsonDocument] = @[], wt = bsonNull()):
  Future[WriteResult]{.multisock.} =
  let privlen = privileges.len
  let rolelen = roles.len
  if privlen == 0 and rolelen == 0:
    result.reason = "Both privileges and roles cannot be empty."
    return
  var q = bson({
    updateRole: name,
  })
  if privlen > 0:
    q["privileges"] = privileges.map toBson
  if rolelen > 0:
    q["roles"] = roles.map toBson
  if authRestrict.len > 0:
    q["authenticationRestriction"] = authRestrict.map toBson
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, "admin")

proc dropRole*(db: Database[AsyncSocket], role: string, wt = bsonNull()):
  Future[WriteResult]{.multisock.} =
  var q = bson({ dropRole: role })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc dropAllRolesFromDatabase*(db: Database[AsyncSocket], wt = bsonNull()):
    Future[WriteResult] {.multisock.} =
  var q = bson({ dropAllRolesFromDatabase: 1 })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

template grantRevoke(db: Database[MultiSock], grname, val, privrole: string,
  wt: BsonBase, prval: untyped): untyped =
  var q = bson()
  q[grname] = val
  q[privrole] = `prval`.map toBson
  q.addWriteConcern(db, wt)
  unown(q)

proc grantPrivilegesToRole*(db: Database[AsyncSocket], role: string, privileges: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.multisock.} =
  let q = db.grantRevoke("grantPrivileges", role, "privileges", wt, privileges)
  result = await db.proceed(q)

proc grantRolesToRole*(db: Database[AsyncSocket], role: string, roles: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.multisock.} =
  let q = db.grantRevoke("grantRolesToRole", role, "roles", wt, roles)
  result = await db.proceed(q)

proc invalidateUserCache*(db: Database[AsyncSocket]): Future[WriteResult] {.multisock.} =
  result = await db.proceed(bson({ invalidateUserCache: 1 }))

proc revokePrivilegesFromRole*(db: Database[AsyncSocket], role: string, privileges: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.multisock.} =
  let q = db.grantRevoke("revokePrivilegesFromRole", role, "privileges", wt, privileges)
  result = await db.proceed(q)

proc revokeRolesFromRole*(db: Database[AsyncSocket], role: string, roles: seq[BsonDocument],
  wt = bsonNull()): Future[WriteResult] {.multisock.} =
  let q = db.grantRevoke("revokeRolesFromRole", role, "roles", wt, roles)
  result = await db.proceed(q)

proc rolesInfo*(db: Database[AsyncSocket], info: BsonBase, showPriv = false,
  showBuiltin = false): Future[ReplyFormat] {.multisock.} =
  let q = bson({
    rolesInfo: info,
    showPrivileges: showPriv,
    showBuiltinRoles: showBuiltin,
  })
  let compression = if db.db.compressions.len > 0: db.db.compressions[0]
                    else: cidNoop
  result = await sendops(q, db, cmd = ckRead, compression = compression)