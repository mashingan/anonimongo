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
  result = await db.proceed(q)

proc dropRole*(db: Database, name: string, wt = bsonNull()):
  Future[(bool, string)]{.async.} =
  var q = bson({ dropRole: name })
  q.addWriteConcern(db, wt)
  result = await db.proceed(q)