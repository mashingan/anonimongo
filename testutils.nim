import asyncdispatch, strformat, deques, tables

import nimsha2

import types, pool, client, auth, bson

proc testsetup*: Mongo =
  when defined(ssl):
    const key {.strdefine.} = "d:/dev/self-signed-cert/key.pem"
    const cert {.strdefine.} = "d:/dev/self-signed-cert/cert.pem"
    let sslinfo = initSSLInfo(key, cert)
  else:
    let sslinfo = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  let mongo = newMongo(poolconn = 2, sslinfo = sslinfo)
  mongo.appname = "Test driver"
  if not waitFor mongo.connect:
    echo "error connecting, quit"
  echo &"current available conns: {mongo.pool.available.len}"
  if not waitFor(authenticate[Sha256Digest](mongo, "rdruffy", "rdruffy")):
    echo "cannot authenticate the connection"
  echo &"is mongo authenticated: {mongo.authenticated}"
  result = mongo