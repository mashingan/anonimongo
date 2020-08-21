import asyncdispatch, tables, uri
import osproc, sugar, unittest
import strformat

import nimSHA2

import ../src/anonimongo

{.warning[UnusedImport]: off.}

const
  pem* {.strdefine.} = "d:/dev/self-signed-cert/srv.key.pem"
  exe* {.strdefine.} =
    when defined windows: "d:/installer/mongodb/bin/mongod"
    else: "mongod"
  key* {.strdefine.} = "d:/dev/self-signed-cert/key.pem"
  cert* {.strdefine.} = "d:/dev/self-signed-cert/cert.pem"
  dbpath* {.strdefine.} = "d:/dev/mongodata"
  filename* {.strdefine.} = ""
  saveas* {.strdefine.} = ""
  user* {.strdefine.} = "rdruffy"
  pass* {.strdefine.} = "rdruffy"
  host* {.strdefine.} = "localhost"
  port* {.intdefine.} = 27017
  poolconn* {.intdefine.} = 2
  localhost* = host == "localhost"
  nomongod* = not defined(nomongod)
  runlocal* = localhost and nomongod

  mongourl {.strdefine, used.} = &"""mongo://rdruffy:rdruffy@localhost:27017/?tlscertificateKeyfile=certificate:{encodeUrl(cert)},key:{encodeUrl(key)}&authSource=admin"""
  verbose = defined(verbose)
  testReplication* {.booldefine.} = true

when verbose:
  import times, strformat

proc startmongo*: Process =
  var args = @[
    "--port", "27017",
    "--dbpath", dbpath,
    "--bind_ip_all",
    "--auth"]
  when defined(ssl):
    args.add "--sslMode"
    args.add "requireSSL"
    args.add "--sslPEMKeyFile"
    args.add pem
    if cert != "":
      args.add "--sslCAFile"
      args.add cert
  when defined(windows):
    # the process cannot continue unless the stdout flushed
    let opt = {poUsePath, poStdErrToStdOut, poInteractive, poParentStreams}
  else:
    let opt = {poUsePath, poStdErrToStdOut}
  result = unown startProcess(exe, args = args, options = opt)

proc withAuth*(m: Mongo): bool =
  (user != "" and pass != "") or m.hasUserAuth

proc testsetup*: Mongo =
  when defined(ssl):
    let sslinfo = initSSLInfo(key, cert)
  else:
    let sslinfo = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  when not defined(uri):
    let mongo = newMongo(host = host, port = port, poolconn = poolconn, sslinfo = sslinfo)
  else:
    let mongo = newMongo(parseUri mongourl, poolconn = poolconn)

  when defined(uri):
    doAssert mongo.db == "admin"

  mongo.appname = "Test driver"
  if not waitFor mongo.connect:
    echo "error connecting, quit"
  #echo &"current available conns: {mongo.pool.available.len}"
  when verbose:
    let start = cpuTime()
  if mongo.withAuth and not waitFor(authenticate[Sha256Digest](mongo, user, pass)):
    echo "cannot authenticate the connection"
  #echo &"is mongo authenticated: {mongo.authenticated}"
  when verbose:
    echo &"auth ended taking {cpuTime() - start} for poolconn {poolconn}"
  result = mongo

proc tell*(label, reason: string) =
  stdout.write label
  dump reason

template reasonedCheck*(b: BsonDocument | bool, label: string, reason = "") =
  when b is BsonDocument:
    check b.ok
    if not b.ok: (label & ": ").tell b.errmsg
  else:
    check b
    if not b: (label & ": ").tell reason

when testReplication:
  import endians, net, streams
  import dnsclient
  # reuse private dnsclient implementation
  from private/protocol as dnsprot import parseResponse, toStream
  from private/utils as dnsutils import writeShort

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
    req.header.ancount = 1
    req.header.rcode = 0
    var head = req.header
    result = head.toStream()
    req.question.kind = SRV
    req.question.toStream(result)
    var srvs = newseq[SRVRecord](3)
    for i in 0 .. 2:
      srvs[i] = SRVRecord(
        name: "localhost",
        class: IN,
        ttl: 60,
        kind: SRV,
        priority: 0,
        port: uint16(27018+i),
        target: "localhost",
        weight: 0)
    result.serialize(srvs, "localhost")

  proc fakeDnsServer* =
    var server = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    server.bindAddr(Port 27016)
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