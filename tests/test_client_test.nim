import unittest, osproc, os, strformat

import utils_test
import anonimongo

var mongorun: Process
if runlocal:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "Client connection and user management tests":
  test "Required mongo is running":
    if runlocal:
      require mongorun.running
    else:
      check true

  var mongo: Mongo[TheSock]
  var db: Database[TheSock]
  var wr: WriteResult

  let existingDb = "temptest"
  let existingUser = bson {
    user: user, db: "admin"
  }
  let newuser = "temptest-user"

  test "Connected mongo and authenticated":
    mongo = testsetup()
    if mongo.withAuth:
      require mongo.authenticated

  test "Look users info":
    require mongo != nil
    db = mongo[existingDb]
    # test looking for not existing user
    when anoSocketSync:
      var reply = db.usersInfo("not-exists0user")
    else:
      var reply = waitFor db.usersInfo("not-exists0user")
    check reply.ok
    check reply["users"].len == 0

    when anoSocketSync:
      reply = db.usersInfo(existingUser)
    else:
      reply = waitFor db.usersInfo(existingUser)
    let users = reply["users"]
    when defined(existingMongoSetup):
      check users.len == 1
      let theuser = users[0]
      check theuser["user"] == user
    else:
      check users.len == 0

  test &"Create new user: {newuser}":
    when anoSocketSync:
      wr = db.createUser(newuser, newuser,
        roles = bsonArray("read"), customData = bson({ role: "testing"}))
    else:
      wr = waitFor db.createUser(newuser, newuser,
        roles = bsonArray("read"), customData = bson({ role: "testing"}))
    wr.success.reasonedCheck("createUser error", wr.reason)
    
    when anoSocketSync:
      var reply = db.usersInfo(newuser)
    else:
      var reply = waitFor db.usersInfo(newuser)
    check reply.ok
    let users = reply["users"]
    check users.len == 1
    let newdoc = users[0].ofEmbedded
    check newdoc["user"] == newuser
    check newdoc["customData"]["role"] == "testing"

  test &"Look for all users in {existingDb}":
    when anoSocketSync:
      let reply = db.usersInfo(1)
    else:
      let reply = waitFor db.usersInfo(1)
    check reply.ok
    check reply["users"].len == 1

  test &"No added {newuser} to admin database":
    when anoSocketSync:
      let reply = db.usersInfo(bson {
        user: newuser, db: "admin",
      })
    else:
      let reply = waitFor db.usersInfo(bson {
        user: newuser, db: "admin",
      })
    check reply.ok
    check reply["users"].len == 0

  test &"Check info of the connected user {db.db.username}":
    when anoSocketSync:
      let reply = db.usersInfo(bson {
        user: db.db.username, db: "admin"
      })
    else:
      let reply = waitFor db.usersInfo(bson {
        user: db.db.username, db: "admin"
      })
    check reply.ok
    let users = reply["users"]

    # This is needed to avoid the tripping of number users in admin when
    # running github action.
    # Since the os used, Ubuntu, has pristine mongo installation so
    # there's no user created for it hence it's always returning zero
    # when checking the users in admin databaes.
    when defined(existingMongoSetup):
      check users.len == 1
    else:
      check users.len == 0

  test &"Grant roles to {newuser}":
    when anoSocketSync:
      wr = db.grantRolesToUser(newuser,
        roles = bsonArray("readWrite"))
    else:
      wr = waitFor db.grantRolesToUser(newuser,
        roles = bsonArray("readWrite"))
    wr.success.reasonedCheck("grantRolesToUser error", wr.reason)

  proc checkUserRoles(checkRoles: seq[string]) {.used.} =
    when anoSocketSync:
      var reply = db.usersInfo(newuser)
    else:
      var reply = waitFor db.usersInfo(newuser)
    check reply.ok
    let users = reply["users"]
    check users.len == 1
    for udoc in users.ofArray:
      let roles = udoc["roles"].ofArray
      check roles.len == checkRoles.len
      for role in roles.ofArray:
        check role["role"] in checkRoles

  test &"Check newly granted roles to {newuser}":
    checkUserRoles @["read", "readWrite"]

  test &"Revoke roles to {newuser}":
    when anoSocketSync:
      wr = db.revokeRolesFromUser(newuser,
        roles = bsonArray("read", "readWrite"))
    else:
      wr = waitFor db.revokeRolesFromUser(newuser,
        roles = bsonArray("read", "readWrite"))
    wr.success.reasonedCheck("revokeRolesFromUser error", wr.reason)

  test &"Check newly revoked roles to {newuser}":
    checkUserRoles @[]

  test &"Update {newuser}":
    when anoSocketSync:
      wr = db.updateUser(newuser, newuser,
        roles = bsonArray("read"))
    else:
      wr = waitFor db.updateUser(newuser, newuser,
        roles = bsonArray("read"))
    wr.success.reasonedCheck("updateUser error", wr.reason)

  test &"Check newly updated roles to {newuser}":
    checkUserRoles @["read"]

  test &"Delete/drop the {newuser}":
    when anoSocketSync:
      wr = db.dropUser(newuser)
    else:
      wr = waitFor db.dropUser(newuser)
    wr.success.reasonedCheck("dropUser error", wr.reason)

  test "Shutdown mongo":
    if runlocal:
      require mongo != nil
      when anoSocketSync:
        wr = mongo.shutdown(timeout = 10)
      else:
        wr = waitFor mongo.shutdown(timeout = 10)
      check wr.success
    else:
      skip()

  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo