import unittest, osproc, os, strformat

import testutils
import core/[types, wire, bson, utils]
import dbops/[admmgmt, client]

const localhost = testutils.host == "localhost"

var mongorun: Process
if localhost:
  mongorun = startmongo()
  sleep 3000 # waiting for mongod to be ready

suite "Client connection and user management tests":
  test "Required mongo is running":
    if localhost:
      require mongorun.running
    else:
      check true

  var mongo: Mongo
  var db: Database

  let existingDb = "temptest"
  let existingUser = bson({
    usersInfo: { user: user, db: "admin" },
  })
  let newuser = "temptest-user"

  test "Connected mongo and authenticated":
    mongo = testsetup()
    require mongo.authenticated

  test "Look users info":
    require mongo != nil
    db = mongo[existingDb]
    # test looking for not existing user
    var reply = waitFor db.usersInfo(bson({
      usersInfo: { user: "not-exists0user", db: "admin"}}))
    var (success, reason) = check reply
    check success
    # test for invalid command
    reply = waitFor db.usersInfo(bson({
      user: "rdruffy", db: "admin"
    }))
    (success, reason) = check reply
    check not success
    "Look user with invalid command: ".tell reason
    reply = waitFor db.usersInfo(existingUser)
    (success, reason) = check reply
    success.reasonedCheck("usersInfo error", reason)

  test &"Create new user: {newuser}":
    let (success, reason) = waitFor db.createUser(newuser, newuser,
      roles = bsonArray("read"), customData = bson({ role: "testing"}))
    success.reasonedCheck("createUser error", reason)

  test &"Grant roles to {newuser}":
    let (success, reason) = waitFor db.grantRolesToUser(newuser,
      roles = bsonArray("readWrite"))
    success.reasonedCheck("grantRolesToUser error", reason)

  test &"Revoke roles to {newuser}":
    let (success, reason) = waitFor db.revokeRolesFromUser(newuser,
      roles = bsonArray("readWrite"))
    success.reasonedCheck("revokeRolesFromUser error", reason)

  test &"Update {newuser}":
    let (success, reason) = waitFor db.updateUser(newuser, newuser,
      roles = bsonArray("read"))
    success.reasonedCheck("updateUser error", reason)

  test &"Delete/drop the {newuser}":
    let (success, reason) = waitFor db.dropUser(newuser)
    success.reasonedCheck("dropUser error", reason)

  test "Shutdown mongo":
    require mongo != nil
    let (success, _) = waitFor db.shutdown(timeout = 10)
    check success

  if localhost:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo