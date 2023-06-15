import asyncdispatch, net, tables, uri
import osproc, sugar, unittest
import strformat

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
  anoSocketSync* = defined(anoSocketSync)

  mongourl {.strdefine, used.} = "mongo://rdruffy:rdruffy@localhost:27017/" &
    "?tlscertificateKeyfile=" &
    &"certificate:{encodeUrl(cert)},key:{encodeUrl(key)}&authSource=admin" &
    "&compressors=snappy,zlib"
  verbose* = defined(verbose)

when verbose:
  import times, strformat

when not anoSocketSync:
  type TheSock* = AsyncSocket
else:
  type TheSock* = Socket

proc startmongo*: Process =
  var args = @[
    "--port", "27017",
    "--dbpath", dbpath,
    "--bind_ip_all",
    "--networkMessageCompressors", "snappy,zlib",
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

proc testsetup*: Mongo[TheSock] =
  when defined(ssl):
    let sslinfo {.used.} = initSSLInfo(key, cert)
  else:
    let sslinfo {.used.} = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  when not defined(uri):
    let mongo = newMongo[TheSock](host = host, port = port, poolconn = poolconn, sslinfo = sslinfo)
  else:
    let mongo = newMongo[TheSock](MongoUri mongourl, poolconn = poolconn)

  mongo.retryableWrites = true
  when defined(uri):
    doAssert mongo.db == "admin"

  mongo.appname = "Test driver"
  when anoSocketSync:
    if not mongo.connect:
      echo "error connecting, quit"
  else:
    if not waitFor mongo.connect:
      echo "error connecting, quit"
  #echo &"current available conns: {mongo.pool.available.len}"
  when verbose:
    let start = cpuTime()
  when anoSocketSync:
    if mongo.withAuth and not mongo.authenticate[:SHA256Digest](user, pass):
      echo "cannot authenticate the connection"
  else:
    if mongo.withAuth and not waitFor mongo.authenticate[:SHA256Digest](user, pass):
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