import uri, tables, strutils
from asyncdispatch import Port

import sha1, nimSHA2

import pool, wire

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

  Database* = ref object of RootObj
    name*: string
    db*: Mongo

  Collection* = object
    name*: string
    dbname: string
    db*: Mongo

  Query* = object
    collname*: string
    dbname*: string
    db*: Mongo

  MongoError* = ref object of Exception

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

proc newMongo*(host = "localhost", port = 27017, master = true,
  poolconn = poolconn): Mongo =
  result = Mongo(
    isMaster: master,
    host: host,
    port: Port port,
    query: newTable[string, seq[string]](),
    pool: initPool(poolconn)
  )

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

proc authenticate[T: SHA1Digest | Sha256Digest](m: Mongo, user, pass: string):
  Future[bool] {.async.} =
  let adm = if m.db != "": (m.db & ".$cmd") else: "admin.$cmd"
  if await m.pool.authenticate(user, pass, T, adm):
    m.authenticated = true
    result = true

proc authenticate[T: SHA1Digest | SHA256Digest](m: Mongo):
  Future[bool] {.async.} =
  if m.username == "" or m.password == "":
    raise newException(MongoError, "username or password not available")
  result = authenticate[T](m, m.username, m.password)

proc `appname=`*(m: Mongo, name: string) =
  m.query["appname"] = @[name]

proc appname*(m: Mongo): string =
  let mq = m.query.getOrDefault("appname")
  if mq.len > 0:
    result = mq[0]
  else:
    result = ""