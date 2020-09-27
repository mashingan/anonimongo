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

  var mongo: Mongo
  var db: Database
  var wr: WriteResult

  let existingDb = "temptest"
  let existingUser = bson({
    usersInfo: { user: user, db: "admin" },
  })
  let newuser = "temptest-user"

  test "Connected mongo and authenticated":
    mongo = testsetup()
    if mongo.withAuth:
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
    wr = waitFor db.createUser(newuser, newuser,
      roles = bsonArray("read"), customData = bson({ role: "testing"}))
    wr.success.reasonedCheck("createUser error", wr.reason)

  test &"Grant roles to {newuser}":
    wr = waitFor db.grantRolesToUser(newuser,
      roles = bsonArray("readWrite"))
    wr.success.reasonedCheck("grantRolesToUser error", wr.reason)

  test &"Revoke roles to {newuser}":
    wr = waitFor db.revokeRolesFromUser(newuser,
      roles = bsonArray("readWrite"))
    wr.success.reasonedCheck("revokeRolesFromUser error", wr.reason)

  test &"Update {newuser}":
    wr = waitFor db.updateUser(newuser, newuser,
      roles = bsonArray("read"))
    wr.success.reasonedCheck("updateUser error", wr.reason)

  test &"Delete/drop the {newuser}":
    wr = waitFor db.dropUser(newuser)
    wr.success.reasonedCheck("dropUser error", wr.reason)

  test "Shutdown mongo":
    if runlocal:
      require mongo != nil
      wr = waitFor mongo.shutdown(timeout = 10)
      check wr.success
    else:
      skip()

  if runlocal:
    if mongorun.running: kill mongorun
    close mongorun
  close mongo