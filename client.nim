import asyncdispatch, tables, deques, strformat
import os, net
when not defined(release):
  import sugar

import types, wire, bson, pool

const
  drivername = "anonimongo"
  description = "nim mongo driver"
  version = "0.1.0"

proc handshake(m: Mongo, s: AsyncSocket, db: string, id: int32,
  appname = "Anonimongo client apps") {.async.} =
  let appname = appname
  let master = if m.isMaster: 1 else: 0
  let q = bson({
    isMaster: master,
    client: {
      application: { name: appname },
      driver: {
        name: drivername & " - " & description,
        version: version,
      },
      os: {
        "type": hostOS,
        architecture: hostCPU,
      }
    }
  })
  when not defined(release):
    echo "Handshake id: ", id
    dump q
  var stream = newStringStream()
  discard stream.prepareQuery(id, 0, opQuery.int32, 0, db,
    0, 1, q)
  await s.send stream.readAll
  when not defined(release):
    look(await s.getReply)
  else:
    discard await s.getReply

proc connect*(m: Mongo): Future[bool] {.async.} =
  try:
    await(m.pool.connect(m.host, m.port.int))
  except:
    echo getCurrentExceptionMsg()
    return
  result = true
  let appname =
    if "appname" in m.query and m.query["appname"].len > 0:
      m.query["appname"][0]
    else: "Anonimongo client apps"
  var ops = newSeqOfCap[Future[void]](m.pool.available.len)
  let dbname = if m.db != "": (m.db & "$.cmd") else: "admin.$cmd"
  for id, c in m.pool.connections:
    ops.add m.handshake(c.socket, dbname, id.int32, appname)
  await all(ops)
  result = true

proc `[]`*(m: Mongo, name: string): Database =
  result.db = m
  result.name = name

proc `[]`*(dbase: Database, name: string): Collection =
  result.name = name
  result.db = dbase.db

when isMainModule:
  when defined(ssl):
    const key {.strdefine.} = "d:/dev/self-signed-cert/key.pem"
    const cert {.strdefine.} = "d:/dev/self-signed-cert/cert.pem"
    let sslinfo = initSSLInfo(key, cert)
  else:
    let sslinfo = SSLInfo(keyfile: "dummykey", certfile: "dummycert")
  let mongo = newMongo(poolconn = 2, sslinfo = sslinfo)
  echo &"is mongo authenticated: {mongo.authenticated}"
  mongo.appname = "Test driver"
  echo &"now mongo app name is {mongo.appname}"
  if not waitFor mongo.connect:
    echo "error connecting, quit"
  echo &"current available conns: {mongo.pool.available.len}"
  sleep 5000
  mongo.pool.close