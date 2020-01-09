import wire, bson
import scram/client
import md5, strformat

proc authenticate(sock: AsyncSocket, user, pass: string,
  T: typedesc = Sha1Digest, dbname = "admin.$cmd"): Future[bool] {.async.} =
  var
    scram = newScramClient[T]()
    stream = newStringStream()
  let
    msg = getMD5 &"{user}:mongo:{pass}"
    fst = scram.prepareFirstMessage(user)
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, dbname, 0, 1, bson({
      saslStart: int32 1,
      mechanism: "SCRAM-SHA-1",
      payload: bsonBinary fst
  }))
  await sock.send stream.readAll
  let res1 = await sock.getReply
  if res1.documents.len > 0 and res1.documents[0]["ok"].get.ofDouble.int32 == 0:
    echo res1.documents[0]["errMsg"].get
    return false

  let
    strres = res1.documents[0]["payload"].get.ofBinary.stringBytes
    msgf = scram.prepareFinalMessage(msg, strres)
  stream = newStringStream()
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, dbname, 0, 1, bson({
    saslContinue: int32 1,
    conversationId: res1.documents[0]["conversationId"].get.ofInt32,
    payload: bsonBinary msgf
  }))
  await sock.send stream.readAll()
  let res2 = await sock.getReply
  if res2.documents.len <= 0 or res2.documents[0]["ok"].get.ofDouble.int32 == 0:
    echo res2.documents[0]["errMsg"].get
    return false
  stream = newStringStream()
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, dbname, 0, 1, bson({
    saslContinue: int32 1,
    conversationId: res2.documents[0]["conversationId"].get.ofInt32,
    payload: bsonBinary ""
  }))
  await sock.send stream.readAll()
  let res3 = await sock.getReply
  if res3.documents.len > 0 and res3.documents[0]["done"].get.ofBool:
    echo "success"
  result = true

when isMainModule:

  var socket = newAsyncSocket()
  waitFor socket.connect("localhost", Port 27017)
  let upass = "rdruffy"
  if waitFor socket.authenticate(upass, upass):
    echo "successfully authenticate"
  else:
    echo "authenticate failed"

  close socket
