import endians, net, streams, os, osproc, strutils, strformat
import dnsclient
from dnsclientpkg/protocol as dnsprot import parseResponse, toStream
from dnsclientpkg/utils as dnsutils import writeShort

from utils_test import verbose, exe

const
  dnsport* {.intdefine.} = 27016
  replicaPortStart* {.intdefine.} = 27018
  keyname {.strdefine.} = "key.pem"
  certname {.strdefine.} = "cert.pem"
  pem {.strdefine.} = "key.priv.pem"
  mongoServer* {.strdefine.} = "localhost"
  uriSettingRepl* = fmt"mongodb://{mongoServer}:{replicaPortStart}/admin?ssl=true"
  uriSrv* = &"mongodb+srv://{mongoServer}/admin?readPreference=secondary"
  uriMultiManual* = &"mongodb://{mongoServer}:{replicaPortStart}," &
    &"{mongoServer}:{replicaPortStart+1},{mongoServer}:{replicaPortStart+2}" &
    "/admin?ssl=true"
  rsetName* = "repltemp"

when verbose:
  import sugar

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
  var req = parseResponse data
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

proc getMongoTemp*: string =
  getTempDir()  / "mongotemp"

proc createMongoTemp*: bool = 
  result = true
  let mongotemp = getMongoTemp()
  try:
    if mongotemp.dirExists:
      removeDir mongotemp
    createDir mongotemp
  except OSError:
    echo "createMongoTemp.OSError: ", getCurrentExceptionMsg()
    result = false

proc createSSLCert*: bool =
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

proc setupMongoReplication*: seq[Process] =
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

proc cleanup*(processes: seq[Process]) =
  for i, process in processes:
    terminate process
    close process

proc cleanMongoTemp* =
  try:
    removeDir getMongoTemp()
  except OSError:
    echo "cleanMongoTemp.OSError: ", getCurrentExceptionMsg()

proc cleanupSSL* =
  let mongotemp = getMongoTemp()
  try:
    removeFile(mongotemp / pem)
    removeFile(certname)
    removeFile(keyname)
  except OSError:
    echo "cleanupSSL OSError: ", getCurrentExceptionMsg()