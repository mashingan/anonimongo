import wire, bson
from sugar import dump
import scram/client
import md5, strformat, base64

proc enc(user, pass: string): string =
  getMD5 &"{user}:mongo:{pass}"

proc handshake(sock: AsyncSocket, user, pass: string) {.async.} =
  var s = newScramClient[Sha1Digest]()
  var stream = newStringStream()
  let msg = getMD5 &"{user}:mongo:{pass}"
  dump msg
  let fst = s.prepareFirstMessage(user)
  dump fst
  let shake1 = bson({
    saslStart: int32 1,
    mechanism: "SCRAM-SHA-1",
    payload: bsonBinary fst
  })
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, "admin.$cmd", 0, 1, shake1)
  await sock.send stream.readAll
  let res1 = await sock.getReply
  dump res1
  let strres = res1.documents[0]["payload"].get.ofBinary.stringBytes
  dump strres
  #let msgf = s.prepareFinalMessage(pass, strres)
  let msgf = s.prepareFinalMessage(msg, strres)
  dump msgf
  let shake2 = bson({
    saslContinue: int32 1,
    conversationId: res1.documents[0]["conversationId"].get.ofInt32,
    payload: bsonBinary msgf
  })
  stream = newStringStream()
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, "admin.$cmd", 0, 1, shake2)
  await sock.send stream.readAll()
  let res2 = await sock.getReply
  dump res2
  if res2.documents.len <= 0 or res2.documents[0]["ok"].get.ofDouble.int32 == 0:
    echo "failed to authenticate"
    return
  stream = newStringStream()
  let shake3 = bson({
    saslContinue: int32 1,
    conversationId: res2.documents[0]["conversationId"].get.ofInt32,
    payload: bsonBinary ""
  })
  #discard stream.prepareQuery(0, 0, opQuery.int32, 0, "admin.$cmd", 0, 1, shake3)
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, "admin.$cmd", 0, 1, bson({
    saslContinue: int32 1,
    conversationId: res2.documents[0]["conversationId"].get.ofInt32,
    payload: bsonBinary ""
  }))
  await sock.send stream.readAll()
  let res3 = await sock.getReply
  dump res3
  if res3.documents.len > 0 and res3.documents[0]["done"].get.ofBool:
    echo "success"

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
  let upass = "rdruffy"
  dump enc("user", "pencil").encode
  waitFor socket.handShake(upass, upass)

#[
  waitFor socket.entryToNewDb("newcoll", "role", bson({
    is_dummy_entry: true,
    `type`: "ephemeral_entry"
  }))

  look( waitFor socket.queryAck("newcoll", "role") )

  #waitFor socket.authenticate
  look( waitFor socket.dropDatabase("newcoll") )
]#
  close socket
