import wire, bson
import scram/client
import md5, strformat

const verbose {.booldefine.} = false

proc authenticate*(sock: AsyncSocket, user, pass: string,
  T: typedesc = Sha256Digest, dbname = "admin.$cmd"): Future[bool] {.async.} =
  ## Authenticate a single asyncsocket based on username and password
  ## and also mechanism for authenticating. Available T for typedesc is
  ## SHA256Digest and SHA1Digest. Default is SHA256Digest and
  ## default database login is ``admin``.
  var
    scram = newScramClient[T]()
    stream = newStringStream()
  when T is Sha1Digest:
    let
      mechanism = "SCRAM-SHA-1"
      msg = getMD5 &"{user}:mongo:{pass}"
  else:
    let
      mechanism = "SCRAM-SHA-256"
      msg = pass
  let fst = scram.prepareFirstMessage(user)

  var q = bson({
    saslStart: int32 1,
    mechanism: mechanism,
    payload: bsonBinary fst,
  })

  when T is SHA256Digest:
    q["options"] = bson({skipEmptyExchange: true})

  discard stream.prepareQuery(0, 0, opQuery.int32, 0, dbname, 0, 1, q)
  await sock.send stream.readAll
  let res1 = await sock.getReply
  if res1.documents.len > 0 and not res1.documents[0].ok:
    if "errmsg" in res1.documents[0]:
      echo res1.documents[0]["errmsg"].get
    elif "$err" in res1.documents[0]:
      echo res1.documents[0]["$err"].get
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
  if res2.documents.len >= 1 and not res2.documents[0].ok:
    let d = res2.documents[0]
    if "errmsg" in d:
      echo d["errmsg"].get
    elif "$err" in d:
      echo d["$err"].get
    return false
  let doc = res2.documents[0]
  if doc.ok and doc["done"].get.ofBool:
    echo "success"
    result = true
    return
  stream = newStringStream()
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, dbname, 0, 1, bson({
    saslContinue: int32 1,
    conversationId: res2.documents[0]["conversationId"].get.ofInt32,
    payload: bsonBinary ""
  }))
  await sock.send stream.readAll()
  when verbose:
    let res3 = await sock.getReply
    if res3.documents.len > 0 and res3.documents[0]["done"].get.ofBool:
      echo "success"
  else:
    discard await sock.getReply
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
