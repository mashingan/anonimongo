import testutils

{.warning[UnusedImport]: off.}

const
  testReplication {.booldefine.} = false

when testReplication and defined(ssl):
  import endians, net, streams, os, osproc, strutils, threadpool,
         unittest, strformat
  from sequtils import allIt, all

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
    #urlSrv {.used.} = &"mongodb+srv://{mongoServer}/admin?readPreferences=secondary"

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
    s.setPosition(0)

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

  proc fakeDnsServer* =
    var server = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    server.bindAddr(Port dnsport)
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
    try:
      createDir getMongoTemp()
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
    createDir mongotemp
    for i in 0 .. 2:
      let repldb = mongotemp / $i
      createDir repldb
      let args = @[
        "--port", $(replicaPortStart+i),
        "--dbpath", repldb,
        "--bind_ip_all",
        "--sslMode", "requireSSL",
        "--sslPEMKeyFile", mongotemp / pem,
        "--replSet", "rs0"
        ]
      when defined(windows):
        let opt = {poUsePath, poStdErrToStdOut, poInteractive, poParentStreams}
      else:
        let opt = {poUsePath, poStdErrToStdOut}
      result[i] = unown startProcess(exe, args = args, options = opt)
      sleep 3000

  proc cleanup(processes: seq[Process]) =
    for i, process in processes:
      kill process
  
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
          MultiUri &"mongodb://{mongoServer}:{replicaPortStart}/admin",
          poolconn = testutils.poolconn)
        defer: m.close()
        check waitfor m.connect()

    test "Connect single uri":
      mongo = newMongo(MultiUri uriSettingRepl,
        poolconn = testutils.poolconn,
        dnsserver = mongoServer,
        dnsport = dnsport)
      require mongo != nil
      require waitfor mongo.connect()
      db = mongo["admin"]
      require db != nil

    test "Setting up replication set":
      var config = bson({
        "_id": "rs0",
        members: [
          { "_id": 0, host: &"{mongoServer}:{replicaPortStart}" },
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
      reply.reasonedCheck("replSetGetStatus")

    test "Restart the replication set":
      let connStatus = waitfor mongo.shutdown(timeout = 10)
      check connStatus.success
      mongo.close
      processes.cleanup
      sleep 3000
      check processes.allIt( not it.running )
      processes = setupMongoReplication()
      require processes.all running

    #spawn fakeDnsServer()
    processes.cleanup
    sleep 3000
    cleanupSSL()
    cleanMongoTemp()