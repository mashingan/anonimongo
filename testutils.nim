import asyncdispatch, tables
import osproc, sugar, unittest

import nimsha2

import types, pool, client, auth, bson, wire

const
  pem* {.strdefine.} = "d:/dev/self-signed-cert/srv.key.pem"
  exe* {.strdefine.} = "d:/installer/mongodb/bin/mongod"
  key* {.strdefine.} = "d:/dev/self-signed-cert/key.pem"
  cert* {.strdefine.} = "d:/dev/self-signed-cert/cert.pem"
  dbpath* {.strdefine.} = "d:/dev/mongodata"
  user* {.strdefine.} = "rdruffy"
  pass* {.strdefine.} = "rdruffy"
  host* {.strdefine.} = "localhost"
  port* {.intdefine.} = 27017

proc startmongo*: Process =
  let args = @[
    "--port", "27017",
    "--dbpath", dbpath,
    "--bind_ip_all",
    "--sslMode", "requireSSL",
    "--sslPEMKeyFile", pem,
    "--auth"]
  when defined(windows):
    # the process cannot continue unless the stdout flushed
    let opt = {poUsePath, poStdErrToStdOut, poInteractive, poParentStreams}
  else:
    let opt = {poUsePath, poStdErrToStdOut}
  result = unown startProcess(exe, args = args, options = opt)

proc testsetup*: Mongo =
  when defined(ssl):
    let sslinfo = initSSLInfo(key, cert)
  else:
    let sslinfo = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  let mongo = newMongo(host = host, port = port, poolconn = 2, sslinfo = sslinfo)
  mongo.appname = "Test driver"
  if not waitFor mongo.connect:
    echo "error connecting, quit"
  #echo &"current available conns: {mongo.pool.available.len}"
  if not waitFor(authenticate[Sha256Digest](mongo, user, pass)):
    echo "cannot authenticate the connection"
  #echo &"is mongo authenticated: {mongo.authenticated}"
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