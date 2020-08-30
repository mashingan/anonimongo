# WIP replication test
# TODO:
# 1. [Done] Run local mongod processes for replication setup
# 2. [Done] Manage the replication setup by initializing it first
#    ref: https://docs.mongodb.com/manual/tutorial/deploy-replica-set-for-testing/
# 3. [Done] Fix all nodes status to be able to elect the PRIMARY, current problem
#    all nodes are SECONDARY and this disability to elect the PRIMARY cannot
#    to do any write operation
# 4. Fix weird `auto` enabling slave during the test and it should be throwing
#    MongoError with reason `not enabled slave`.
# 5. [Done] Cleanup all produced artifacts such as temporary dbpath directories and
#    created self-signing key, certificate, and pem file.
# 6. [Done w ReadPreferences.primary?] Since the test purposely choose
#    the ReadPreferences.secondary, testing to read the database entry
#    could result in disaster because of eventual synchronization.

import utils_test

{.warning[UnusedImport]: off.}

const
  testReplication {.booldefine.} = false

when testReplication and defined(ssl):
  import endians, net, streams, os, osproc, strutils, threadpool,
         unittest, strformat, times
  from sequtils import allIt, all, map, anyIt
  from sugar import dump

  import dnsclient
  # reuse private dnsclient implementation
  from private/protocol as dnsprot import parseResponse, toStream
  from private/utils as dnsutils import writeShort

  import anonimongo

  const
    dnsport {.intdefine.} = 27016
    replicaPortStart {.intdefine.} = 27018
    keyname {.strdefine.} = "key.pem"
    certname {.strdefine.} = "cert.pem"
    pem {.strdefine.} = "key.priv.pem"
    mongoServer {.strdefine.} = "localhost"
    uriSettingRepl = &"mongodb://{mongoServer}:{replicaPortStart}/admin?ssl=true"
    uriSrv = &"mongodb+srv://{mongoServer}/admin?readPreferences=secondary"
    uriMultiManual = &"mongodb://{mongoServer}:{replicaPortStart}," &
      &"{mongoServer}:{replicaPortStart+1},{mongoServer}:{replicaPortStart+2}" &
      "/admin?ssl=true"
    rsetName = "repltemp"

  proc writeName(s: StringStream, srv: SRVRecord, server: string) =
    for sdot in server.split('.'):
      s.write sdot.len.byte
      s.write sdot
    s.write 0x00.byte

  proc serialize(s: StringStream, srv: SRVRecord, server: string) =
    srv.rdlength = srv.priority.sizeof + srv.weight.sizeof +
      srv.port.sizeof
    let domsrv = server.split('.')
    for sdot in domsrv:
      srv.rdlength += byte.sizeof.uint16 + sdot.len.uint16
    srv.rdlength += byte.sizeof.uint16
    s.writeName srv, srv.name
    s.writeShort srv.kind.uint16
    s.writeShort srv.class.uint16

    var ttl: int32
    bigEndian32(addr ttl, addr srv.ttl)
    s.write ttl

    s.writeShort srv.rdlength
    s.writeShort srv.priority
    s.writeShort srv.weight
    s.writeShort srv.port
    s.writeName srv, server

  proc serialize(s: StringStream, srvs: seq[SRVRecord], server: string) =
    for srv in srvs:
      s.serialize srv, server

  proc serialize(data: string): StringStream =
    var req = data.newStringStream.parseResponse
    req.header.qr = QR_RESPONSE
    req.header.ancount = 3
    req.header.rcode = 0
    var head = req.header
    result = head.toStream()
    req.question.kind = SRV
    req.question.toStream(result)
    var srvs = newseq[SRVRecord](3)
    for i in 0 .. 2:
      srvs[i] = SRVRecord(
        name: mongoServer,
        class: IN,
        ttl: 60,
        kind: SRV,
        priority: 0,
        port: uint16(replicaPortStart+i),
        target: mongoServer,
        weight: 0)
    result.serialize(srvs, mongoServer)
    result.setPosition(0)

  proc fakeDnsServer* =
    var server = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    server.bindAddr(Port dnsport)
    defer: close server
    var
      data = ""
      address = ""
      senderport: Port
      length = 64
    try:
      discard server.recvFrom(data, length, address, senderport)
      let restream = serialize data
      let datares = restream.readAll
      server.sendTo(address, senderport, datares)
    except OSError:
      echo "Error socket.recvFrom(): ", getCurrentExceptionMsg()

  proc getMongoTemp: string =
    getTempDir()  / "mongotemp"
  
  proc createMongoTemp: bool = 
    result = true
    let mongotemp = getMongoTemp()
    try:
      if mongotemp.dirExists:
        removeDir mongotemp
      createDir mongotemp
    except OSError:
      echo "createMongoTemp.OSError: ", getCurrentExceptionMsg()
      result = false

  proc createSSLCert: bool =
    var process = startProcess("openssl", args = @[
      "req", "-newkey", "rsa:4096", "-nodes", "-x509", "-days", "365",
      "--outform", "PEM",
      "-keyout", keyname, "-out", certname,
      "-subj", "/C=US/ST=Denial/L=Springfield/O=Dis/CN=temp.com"],
      options = {poUsePath, poStdErrToStdOut, poInteractive, poParentStreams})
    result = process.waitForExit == 0
    if result:
      pem.writeFile(readFile(keyname) & readFile(certname))
      try:
        pem.moveFile(getMongoTemp() / pem)
      except OSError:
        echo "createSSLcert.moveFile: ", getCurrentExceptionMsg()
        result = false
    else:
      result = false

  proc setupMongoReplication: seq[Process] =
    result = newseq[Process](3)
    let mongotemp = getMongoTemp()
    for i in 0 .. 2:
      let repldb = mongotemp / $i
      createDir repldb
      let args = @[
        "--replSet", rsetName,
        "--port", $(replicaPortStart+i),
        "--dbpath", repldb,
        "--bind_ip_all",
        "--sslMode", "requireSSL",
        "--sslPEMKeyFile", mongotemp / pem,
        "--oplogSize", "128"
        ]
      when verbose:
        dump args
      when defined(windows):
        let opt = {poUsePath, poStdErrToStdOut, poInteractive, poParentStreams}
      else:
        let opt = {poUsePath, poStdErrToStdOut}
      result[i] = unown startProcess(exe, args = args, options = opt)
      sleep 3000

  proc cleanup(processes: seq[Process]) =
    for i, process in processes:
      terminate process
      close process
  
  proc cleanMongoTemp =
    try:
      removeDir getMongoTemp()
    except OSError:
      echo "cleanMongoTemp.OSError: ", getCurrentExceptionMsg()
  
  proc cleanupSSL =
    let mongotemp = getMongoTemp()
    try:
      removeFile(mongotemp / pem)
      removeFile(certname)
      removeFile(keyname)
    except OSError:
      echo "cleanupSSL OSError: ", getCurrentExceptionMsg()

  suite "Replication, SSL, and SRV DNS seedlist lookup (mongodb+srv) tests":
    test "Initial test setup":
      require createMongoTemp()
    test "Create self-signing SSL key certificate":
      require createSSLCert()
    var processes: seq[Process]
    test "Run the local replication set db":
      processes = setupMongoReplication()
      require processes.allIt( it != nil )
      require processes.all running

    var mongo: Mongo
    var db: Database
    test "Catch error without SSL for SSL/TLS required connection":
      expect(IOError):
        var m = newMongo(
          MongoUri &"mongodb://{mongoServer}:{replicaPortStart}/admin",
          poolconn = utils_test.poolconn)
        check waitfor m.connect()
        m.close()

    test "Connect single uri":
      mongo = newMongo(MongoUri uriSettingRepl,
        poolconn = utils_test.poolconn,
        dnsserver = mongoServer,
        dnsport = dnsport)
      require mongo != nil
      require waitfor mongo.connect()
      db = mongo["admin"]
      require db != nil

    test "Setting up replication set":
      var config = bson({
        "_id": rsetName,
        members: [
          { "_id": 0, host: &"{mongoServer}:{replicaPortStart}", priority: 2 },
          { "_id": 1, host: &"{mongoServer}:{replicaPortStart+1}" },
          { "_id": 2, host: &"{mongoServer}:{replicaPortStart+2}" },
        ]
      })
      var reply: BsonDocument
      try:
        reply = waitfor db.replSetInitiate(config)
      except MongoError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      reply.reasonedCheck("replSetInitiate")
      try:
        reply = waitfor db.replSetGetStatus
      except MongoError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      when verbose: dump reply
      reply.reasonedCheck("replSetGetStatus")
      check reply["set"] == rsetName
      let members = reply["members"].ofArray
      check members.len == 3
    sleep 15_000 # waiting the replica set to elect primary

    test "Connect with manual multi uri connections":
      mongo = newMongo(
        MongoUri uriMultiManual,
        poolconn = utils_test.poolconn
      )
      require mongo != nil
      check waitfor mongo.connect
      db = mongo["admin"]
      let cfg = waitfor db.replSetGetStatus
      let members = cfg["members"].ofArray
      check members.len == 3
      check members.anyIt( it["stateStr"] == "PRIMARY" )
      mongo.close

    spawn fakeDnsServer()
    test "Check newMongo mongodb+srv scheme connection":
      try:
        mongo = newMongo(
          MongoUri uriSrv,
          poolconn = utils_test.poolconn,
          dnsserver = mongoServer,
          dnsport = dnsport
        )
      except RangeError:
        checkpoint(getCurrentExceptionMsg())
        fail()
      require mongo != nil
      require waitfor mongo.connect
      db = mongo["temptest"]
      require db != nil
    sync()

    var tempcoll = db["test"]
    let
      currtime = now().toTime
      msg = "こんにちは、isekai"
      truthy = true
      embedobj = bson({
        "type": "kawaii",
        name: "Est",
        form: "Sword",
      })

    test "Reconnect to enable replication set writing":
      skip()
      mongo.slaveOk
      #require waitfor mongo.connect
      db = mongo["temptest"]
      require db != nil
      #sync()
      #mongo.slaveOk
      tempcoll = db["test"]
      check true

    test "Retry inserting to database":
      tempcoll = db["test"]
      let b = bson({
        entry: currtime,
        msg: msg,
        truthness: truthy,
        embedded: embedobj,
      })
      let wr = waitfor tempcoll.insert(@[b])
      wr.success.reasonedCheck("Retry tempcoll.insert", wr.reason)

    discard waitfor mongo.shutdown(timeout = 10)
    mongo.close
    processes.cleanup
    sleep 3000
    cleanupSSL()
    cleanMongoTemp()
