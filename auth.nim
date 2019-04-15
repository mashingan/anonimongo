import wire, bson
from sugar import dump

proc authenticate(sock: AsyncSocket) {.async.} =
  let q = newbson(
    ("user", "readwrite".toBson),
    ("pwd", "readwrite".toBson)
  )
  dump q
  var s = newStringStream()
  discard s.prepareQuery(0, 0, opQuery.int32, 0, "reporting.$cmd",
    0, 1, q)
  await sock.send s.readAll
  discard await sock.getReply

proc entryToNewDb(s: AsyncSocket, dbname, collname: string, entry: BsonDocument) {.async.} =
  var stream = newStringStream()
  let insertEntry = bson({
    insert: collname,
    documents: [entry]
  })
  dump insertEntry
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, dbname & ".$cmd",
    0, 1, insertEntry)
  await s.send stream.readAll
  discard await s.getReply

proc findAll(s: AsyncSocket, fullname: string) {.async.} =
  var stream = newStringStream()
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, fullname,
    0, 0)
  await s.send stream.readAll
  discard await s.getReply


when isMainModule:

  var socket = newAsyncSocket()
  waitFor socket.connect("localhost", Port 27017)

  waitFor socket.entryToNewDb("newcoll", "role", bson({
    is_dummy_entry: true,
    `type`: "ephemeral_entry"
  }))

  discard waitFor socket.queryAck("newcoll", "role")

  #waitFor socket.authenticate
  waitFor socket.dropDatabase("newcoll")

  close socket
