import sequtils
import bson, types, wire, utils

proc createRole*(db: Database, name: string, privileges, roles: seq[BsonDocument],
  authRestrict: seq[BsonDocument] = @[], wt = bsonNull()):
  Future[(bool, string)]{.async.} =
  var q = bson({
    createRole: name,
    privileges: privileges.map toBson,
    roles: roles.map toBson,
  })
  if authRestrict.len >= 0:
    q["authenticationRestriction"] = authRestrict.map toBson
  q.addWriteConcern(db, wt)
  result = await db.proceed(q, "admin")

proc dropRole*(db: Database, role: string, wt = bsonNull()):
  Future[(bool, string)]{.async.} =
  var q = bson({ dropRole: role })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc dropAllRolesFromDatabase*(db: Database, wt = bsonNull()):
    Future[(bool, string)] {.async.} =
  var q = bson({ dropAllRolesFromDatabase: 1 })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc grantPrivilegesToRole*(db: Database, role: string, privileges: seq[BsonDocument],
  wt = bsonNull()): Future[(bool, string)] {.async.} =
  var q = bson({
    grantPrivilegesToRole: role,
    privileges: privileges.map toBson,
  })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)

proc grantRolesToRole*(db: Database, role: string, roles: seq[BsonDocument],
  wt = bsonNull()): Future[(bool, string)] {.async.} =
  var q = bson({
    grantRolesToRole: role,
    roles: roles.map toBson
  })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)