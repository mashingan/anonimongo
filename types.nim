import uri, tables, strutils, net
from asyncdispatch import Port

import sha1, nimSHA2

import pool, wire, bson

const poolconn* {.intdefine.} = 64

type
  Mongo* = ref object of RootObj
    isMaster*: bool
    tls: bool
    authenticated: bool
    host: string
    port: Port
    username: string
    password: string
    db*: string
    query: TableRef[string, seq[string]]
    pool*: Pool
    writeConcern*: BsonDocument
    flags: QueryFlags

  SslInfo* = object
    keyfile*: string
    certfile*: string
    when defined(ssl):
      protocol*: SslProtVersion

  Database* = ref object of RootObj
    name*: string
    db*: Mongo

  Collection* = object
    name*: string
    dbname: string
    db*: Database

  Cursor* = object
    id*: int64
    firstBatch*: seq[BsonDocument]
    nextBatch*: seq[BsonDocument]
    db*: Mongo
    ns*: string

  MongoError* = object of Exception

proc decodeQuery(s: string): TableRef[string, seq[string]] =
  result = newTable[string, seq[string]]()
  for kv in s.split('&'):
    let kvsarr = kv.split(',')
    for ksvs in kvsarr:
      let kvsvr = ksvs.split('=')
      let k = kvsvr[0]
      let v = if kvsvr.len > 1: kvsvr[1] else: ""
      if k in result:
        result[k].add v
      else:
        result[k] = @[v]

when defined(ssl):
  proc initSslInfo*(keyfile, certfile: string, prot = protSSLv23): SSLInfo =
    result = SSLInfo(
      keyfile: keyfile,
      certfile: certfile,
      protocol: prot
    )

proc newMongo*(host = "localhost", port = 27017, master = true,
  poolconn = poolconn, sslinfo = SslInfo()): Mongo =
  result = Mongo(
    isMaster: master,
    host: host,
    port: Port port,
    query: newTable[string, seq[string]](),
    pool: initPool(poolconn)
  )
  if sslinfo.keyfile != "" and sslinfo.certfile != "":
    when defined(ssl):
      let ctx = newContext(protVersion = sslinfo.protocol,
        certFile = sslinfo.certfile,
        keyfile = sslinfo.keyfile,
        verifyMode = CVerifyNone)
      for _, c in result.pool.connections:
        echo "wrapping ssl socket"
        ctx.wrapSocket(c.socket)
      result.tls = true

proc newMongo*(uri: Uri, master = true, poolconn = poolconn): Mongo =
  let port = try: parseInt(uri.port)
             except ValueError: 27017
  result = Mongo(
    isMaster: master,
    host: uri.hostname,
    username: uri.username,
    password: uri.password,
    port: Port port,
    query: decodeQuery(uri.query),
    pool: initPool(poolconn)
  )

proc tls*(m: Mongo): bool = m.tls
proc authenticated*(m: Mongo): bool = m.authenticated
proc host*(m: Mongo): string = m.host
proc port*(m: Mongo): Port = m.port
proc query*(m: Mongo): lent TableRef[string, seq[string]] =
  m.query
proc flags*(m: Mongo): QueryFlags = m.flags

proc authenticate*[T: SHA1Digest | Sha256Digest](m: Mongo, user, pass: string):
  Future[bool] {.async.} =
  let adm = if m.db != "": (m.db & ".$cmd") else: "admin.$cmd"
  if await m.pool.authenticate(user, pass, T, adm):
    m.authenticated = true
    result = true

proc authenticate*[T: SHA1Digest | SHA256Digest](m: Mongo):
  Future[bool] {.async.} =
  if m.username == "" or m.password == "":
    raise newException(MongoError, "username or password not available")
  result = await authenticate[T](m, m.username, m.password)

proc `appname=`*(m: Mongo, name: string) =
  m.query["appname"] = @[name]

proc appname*(m: Mongo): string =
  let mq = m.query.getOrDefault("appname")
  if mq.len > 0:
    result = mq[0]
  else:
    result = ""

proc tailableCursor*(m: Mongo) =
  m.flags.incl Flags.TailableCursor

proc slaveOk*(m: Mongo) =
  m.flags.incl Flags.SlaveOk

proc `[]`*(m: Mongo, name: string): Database =
  new result
  result.db = m
  result.name = name

proc `[]`*(dbase: Database, name: string): Collection =
  result.name = name
  result.db = dbase

proc dbname*(cur: Cursor): string = cur.ns.split('.', 1)[0]
proc collname*(cur: Cursor): string = cur.ns.split('.', 1)[1]

proc close*(m: Mongo) = close m.pool