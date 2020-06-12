import uri, tables, strutils, net, strformat, sequtils, unicode
import openssl
from asyncdispatch import Port

import sha1, nimSHA2

import pool, wire, bson

const
  poolconn* {.intdefine.} = 64
  verbose* {.booldefine.} = false
  verifypeer* = defined(verifypeer)
  cafile* {.strdefine.} = ""

type
  Mongo* = ref object of RootObj
    ## An ref object that will handle any necessary information
    ## as Mongo client. Since Mongo expected to live as long as
    ## the program alive, it can be expected to be a singleton
    ## throughout the program, however any lib user can spawn any
    ## instance of Mongo as like, but this should be avoided because
    ## of costly invocation of Mongo.
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
    ## SslInfo will handle information for connecting with SSL/TLS
    ## connection.
    keyfile*: string  ## Key file path
    certfile*: string ## Certificate file path
    when defined(ssl):
      protocol*: SslProtVersion ## The SSL/TLS protocol

  Database* = ref object of RootObj
    ## Database holds the `Mongo<#Mongo>`_ data as ``db`` field.
    name*: string
    db*: Mongo

  Collection* = ref object
    ## Collection holds the `Database<#Database>`_
    ## data as ``db`` field.
    name*: string ## Collection name
    dbname: string ## Database name, easier than ``coll.db.name``
    db*: Database

  Cursor* = object
    ## An object that will short-lived in a handle to fetch more data
    ## with the same identifier. Usually used for find queries variant.
    id*: int64
    firstBatch*: seq[BsonDocument]
    nextBatch*: seq[BsonDocument]
    db*: Database
    ns*: string

  Query* = object
    ## Query is basically any options that will be used when calling dbcommand
    ## find and others related commands. Must of these values are left to be
    ## default with only exception of query field.
    ## ``sort``, ``projection``, ``writeConcern`` all are `BsonBase`_ instead of
    ## `BsonDocument`_ because `BsonBase`_ is more flexible.
    ##
    ## .. _BsonBase: bson.html#BsonBase
    ## .. _BsonDocument: bson.html#BsonDocument
    query*: BsonDocument
    sort*: BsonBase
    projection*: BsonBase
    writeConcern*: BsonBase
    collection*: Collection
    skip*, limit*, batchSize*: int32
    readConcern*, max*, min*: BsonBase

  WriteKind* = enum
    wkSingle wkMany
    
  WriteResult* = object
    ## WriteResult is the result representing the write
    ## operations. The kind of wkSingle means represent
    ## the affected written/changed documents and wkMany
    ## the has that.
    success*: bool
    reason*: string
    case kind*: WriteKind
    of wkMany:
      n*: int
      errmsgs*: seq[string] ## For various error message when writing.
    of wkSingle:
      discard

  BulkResult* = object
    ## A result object for bulk write operations.
    nInserted*, nModified*, nRemoved*: int
    writeErrors*: seq[string]
  
  GridFS* = ref object
    ## GridFS is basically just a object that represents two different
    ## collections: i.e.
    ##
    ## 1. {bucket.name}.files
    ## 2. {bucket.name}.chunks
    ##
    ## Which bucket.files stores the file information itself while
    ## bucket.chunks stores the actual binary information for the
    ## related files.
    name*: string
    files*: Collection
    chunks*: Collection
    chunkSize*: int32

  MongoError* = object of Defect

proc decodeQuery(s: string): TableRef[string, seq[string]] =
  result = newTable[string, seq[string]]()
  if s == "": return
  for kv in s.split('&'):
    let kvsarr = kv.split('=')
    if kvsarr.len > 1:
      let key = kvsarr[0].toLower
      let val = kvsarr[1]
      let kvals = val.split(',')
      for kval in kvals:
        if key in result:
          result[key].add kval
        else:
          result[key] = @[kval]
    else:
      result[kv] = @[]

when defined(ssl) or defined(nimdoc):
  proc initSslInfo*(keyfile, certfile: string, prot = protSSLv23): SSLInfo =
    ## Init the SSLinfo which give default value of protocol to
    ## protSSLv23. It's preferable used when user want to use
    ## SSL/TLS connection.
    result = SSLInfo(
      keyfile: keyfile,
      certfile: certfile,
      protocol: prot
    )

proc setSsl(m: Mongo, sslinfo: SslInfo) =
  if sslinfo.keyfile != "" and sslinfo.certfile != "":
    when defined(ssl):
      let mode = when verifypeer: CVerifyPeer
                 else: CVerifyNone
      let ctx = newContext(protVersion = sslinfo.protocol,
        certfile = sslinfo.certfile,
        keyfile = sslinfo.keyfile,
        verifyMode = mode)
      if verifypeer and cafile == "":
        discard ctx.context.SSL_CTX_load_verify_locations(
          cstring sslinfo.certfile, nil)
      elif verifypeer:
        discard ctx.context.SSL_CTX_load_verify_locations(
          cstring cafile, nil)
      for i, c in m.pool.connections:
        when verbose: echo &"wrapping ssl socket {i}"
        ctx.wrapSocket c.socket
      m.tls = true

proc newMongo*(host = "localhost", port = 27017, master = true,
  poolconn = poolconn, sslinfo = SslInfo()): Mongo =
  ## Give a new `Mongo<#Mongo>`_ instance manually from given parameters.
  result = Mongo(
    isMaster: master,
    host: host,
    port: Port port,
    query: newTable[string, seq[string]](),
    pool: initPool(poolconn)
  )
  result.setSsl sslInfo

proc newMongo*(uri: Uri, master = true, poolconn = poolconn): Mongo =
  ## Give a new `Mongo<#Mongo>`_ instance based on URI string.
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
  if "w" in result.query and result.query["w"].len > 0:
    # "w" here can be a number or a string.
    let val = result.query["w"][0]
    if val.all isDigit:
      writeConcern["w"] = try: (parseInt val).toBson
                          except: 1.toBson
    else:
      writeConcern["w"] = val
  if "j" in result.query and result.query["j"].len > 0:
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
  if "authSource".toLower in result.query:
    result.db = result.query["authsource"][0]

  proc setCertKey (s: var SslInfo, vals: seq[string]) =
    for kv in vals:
      let kvs = kv.split ':'
      if kvs[0].toLower == "certificate":
        s.certfile = decodeUrl kvs[1]
      elif kvs[0].toLower == "key":
        s.keyfile = decodeUrl kvs[1]
  var newsslinfo = SSlInfo()
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

proc hasUserAuth*(m: Mongo): bool =
  m.username != "" and m.password != ""

proc authenticate*[T: SHA1Digest | Sha256Digest](m: Mongo, user, pass: string):
  Future[bool] {.async.} =
  ## Authenticate Mongo with given username and password and delegate it to
  ## `pool.authenticate<pool.html#authenticate,Pool,string,string,typedesc,string>`_.
  let adm = if m.db != "": (m.db & ".$cmd") else: "admin.$cmd"
  if await m.pool.authenticate(user, pass, T, adm):
    m.authenticated = true
    result = true

proc authenticate*[T: SHA1Digest | SHA256Digest](m: Mongo):
  Future[bool] {.async.} =
  ## Authenticate Mongo with available username and password from
  ## `Mongo<#Mongo>`_ object and delegate it to
  ## `pool.authenticate<pool.html#authenticate,Pool,string,string,typedesc,string>`_.
  if m.username == "" or m.password == "":
    raise newException(MongoError, "username or password not available")
  result = await authenticate[T](m, m.username, m.password)

proc `appname=`*(m: Mongo, name: string) =
  ## Set appname for `Mongo<#Mongo>`_ client instance.
  m.query["appname"] = @[name]

proc appname*(m: Mongo): string =
  ## Get appname from `Mongo<#Mongo>`_ client instance.
  let mq = m.query.getOrDefault("appname")
  if mq.len > 0:
    result = mq[0]
  else:
    result = ""

proc tailableCursor*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to support TailableCursor
  m.flags.incl Flags.TailableCursor

proc noTailable*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to not support TailableCursor
  m.flags.excl Flags.TailableCursor

proc slaveOk*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to support SlaveOk flag
  m.flags.incl Flags.SlaveOk

proc noSlave*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to not support SlaveOk flag
  m.flags.excl Flags.SlaveOk

proc `[]`*(m: Mongo, name: string): Database =
  ## Give new Database from `Mongo<#Mongo>`_,
  ## expected to long-live object.
  new result
  result.db = m
  result.name = name

proc `[]`*(dbase: Database, name: string): Collection =
  ## Give new `Collection<#Collection>`_ from
  ## `Database<#Database>`_, expected to long-live object.
  new result
  result.name = name
  result.dbname = dbase.name
  result.db = dbase

proc dbname*(cur: Cursor): string = cur.ns.split('.', 1)[0]
  ## Get `Database<#Database>`_, name from Cursor.
proc collname*(cur: Cursor): string = cur.ns.split('.', 1)[1]
  ## Get `Collection<#Collection>`_ name from Cursor.

proc close*(m: Mongo) = close m.pool

proc initQuery*(query = bson(), collection: Collection = nil,
  skip = 0'i32, limit = 0'i32, batchSize = 101'i32): Query =
  ## Init `query<#Query>`_ to be used for next find.
  ## Apparently this should be used for Query Plan Cache
  ## however currently the lib still hasn't support that feature yet.
  result = Query(
    query: query,
    collection: collection,
    skip: skip,
    limit: limit,
    batchSize: batchSize)