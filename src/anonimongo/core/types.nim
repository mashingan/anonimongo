import uri, tables, strutils, net, strformat, sequtils, unicode
from asyncdispatch import Port
import sugar

import sha1, nimSHA2

import pool, wire, bson

const
  poolconn* {.intdefine.} = 64
  verbose* {.booldefine.} = false

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

  Collection* = ref object
    name*: string
    dbname: string
    db*: Database

  Cursor* = object
    id*: int64
    firstBatch*: seq[BsonDocument]
    nextBatch*: seq[BsonDocument]
    db*: Database
    ns*: string

  Query* = object
    ## Query is basically any options that will be used when calling dbcommand
    ## find and others related commands. Must of these values are left to be
    ## default with only exception of query field.
    query*: BsonDocument
    sort*: BsonBase
    projection*: BsonBase
    writeConcern*: BsonBase
    collection*: Collection
    skip*, limit*, batchSize*: int32
    readConcern*, max*, min*: BsonBase

  MongoError* = object of Exception

proc decodeQuery(s: string): TableRef[string, seq[string]] =
  result = newTable[string, seq[string]]()
  for kv in s.split('&'):
    let kvsarr = kv.split('=')
    let key = kvsarr[0].toLower
    let val = kvsarr[1]
    if kvsarr.len > 1:
      let kvals = val.split(',')
      for kval in kvals:
        if key in result:
          result[key].add kval
        else:
          result[key] = @[kval]
    else:
      result[key] = @[]

when defined(ssl):
  proc initSslInfo*(keyfile, certfile: string, prot = protSSLv23): SSLInfo =
    result = SSLInfo(
      keyfile: keyfile,
      certfile: certfile,
      protocol: prot
    )

proc setSsl(m: Mongo, sslinfo: SslInfo) =
  if sslinfo.keyfile != "" and sslinfo.certfile != "":
    when defined(ssl):
      let ctx = newContext(protVersion = sslinfo.protocol,
        certfile = sslinfo.certfile,
        keyfile = sslinfo.keyfile,
        verifyMode = CVerifyNone)
      for i, c in m.pool.connections:
        when verbose: echo &"wrapping ssl socket {i}"
        ctx.wrapSocket c.socket
      m.tls = true

proc newMongo*(host = "localhost", port = 27017, master = true,
  poolconn = poolconn, sslinfo = SslInfo()): Mongo =
  result = Mongo(
    isMaster: master,
    host: host,
    port: Port port,
    query: newTable[string, seq[string]](),
    pool: initPool(poolconn)
  )
  result.setSsl sslInfo

proc newMongo*(uri: Uri, master = true, poolconn = poolconn,
  sslInfo = SslInfo()): Mongo =
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
  if result.host == "": result.host = "localhost"
  # need elaborate handling for URI connect
  # ref:https://github.com/mongodb/specifications/blob/master/source/uri-options/uri-options.rst 
  var writeConcern = bson()
  if "w" in result.query and result.query["w"].len > 1:
    #[
    writeConcern["w"] = try: parseInt result.query["m"][0].toBson
                        except: (-1).toBson
                        ]#
    let val = result.query["w"][0]
    if val.all isDigit:
      writeConcern["w"] = try: (parseInt val).toBson
                          except: 1.toBson
    else:
      writeConcern["w"] = val
  if "j" in result.query and result.query["j"].len > 1:
    writeConcern["j"] = result.query["j"][0]

  if "appname" notin result.query:
    result.query["appname"] = @["Anonimongo driver client apps"]
  let tlsCertInval = ["tlsInsecure", "tlsAllowInvalidCertificates"]
  let tlsHostInval = ["tlsInsecure", "tlsAllowInvalidHostnames"]
  if tlsCertInval.allIt(it.toLower in result.query):
    raise newException(MongoError,
      &"""Can't have {tlsCertInval.join(" and ")}""")
  if tlsHostInval.allIt(it.toLower in result.query):
    raise newException(MongoError,
      &"""Can't have {tlsHostInval.join(" and ")}""")

  proc setCertKey (s: var SslInfo, vals: seq[string]) =
    for kv in vals:
      let kvs = kv.split ':'
      if kvs[0].toLower == "certificate":
        s.certfile = decodeUrl kvs[1]
      elif kvs[0].toLower == "key":
        s.keyfile = decodeUrl kvs[1]
  var newsslinfo = sslinfo
  if ["ssl", "tls"].anyIt( it.toLower in result.query):
    if "tlsCertificateKeyFile".toLower notin result.query:
      raise newException(MongoError, "option tlsCertificateKeyFile not provided")
    newsslinfo.setCertKey result.query["tlsCertificateKeyFile".toLower]
  elif "tlsCertificateKeyFile".toLower in result.query:
    echo "got tls certificate key"
    newsslinfo.setCertKey result.query["tlsCertificatekeyFile".toLower]

  when defined(ssl):
    newsslinfo.protocol = protSSLv23
  result.setSsl newsslinfo
  if not writeConcern.isNil:
    result.writeConcern = writeConcern

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

proc noTailable*(m: Mongo) =
  m.flags.excl Flags.TailableCursor

proc slaveOk*(m: Mongo) =
  m.flags.incl Flags.SlaveOk

proc noSlave*(m: Mongo) =
  m.flags.excl Flags.SlaveOk

proc `[]`*(m: Mongo, name: string): Database =
  new result
  result.db = m
  result.name = name

proc `[]`*(dbase: Database, name: string): Collection =
  new result
  result.name = name
  result.dbname = dbase.name
  result.db = dbase

proc dbname*(cur: Cursor): string = cur.ns.split('.', 1)[0]
proc collname*(cur: Cursor): string = cur.ns.split('.', 1)[1]

proc close*(m: Mongo) = close m.pool

proc initQuery*(query = bson(), collection: Collection = nil,
  skip = 0'i32, limit = 0'i32, batchSize = 101'i32): Query =
  result = Query(
    query: query,
    collection: collection,
    skip: skip,
    limit: limit,
    batchSize: batchSize)