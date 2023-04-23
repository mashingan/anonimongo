import uri, tables, strutils, net, strformat, sequtils, unicode
import deques, sugar
from asyncdispatch import Port
from math import nextPowerOfTwo

when defined(ssl):
  import openssl

import sha1, nimSHA2
import dnsclient

import pool, wire, bson, multisock

export SHA1Digest, SHA256Digest

const
  poolconn* {.intdefine.} = 64
  verbose* = defined(verbose)
  verifypeer* = defined(verifypeer)
  cafile* {.strdefine.} = ""
  withSsl = defined(ssl)
  sslProtVersion {.strdefine, used.} = ""

when verbose:
  import sugar

type
  MongoConn* {.multisock.} = ref object of RootObj
    ## Actual ref object that handles the connection to the intended server
    isMaster*: bool
    host: string
    port: Port
    username: string
    password: string
    pool*: Pool[AsyncSocket]
    authenticated: bool

  Mongo* {.multisock.} = ref object of RootObj
    ## An ref object that will handle any necessary information
    ## as Mongo client. Since Mongo expected to live as long as
    ## the program alive, it can be expected to be a singleton
    ## throughout the program, however any lib user can spawn any
    ## instance of Mongo as like, but this should be avoided because
    ## of costly invocation of Mongo.
    hosts*: seq[string]
    primary*: string
    servers*: TableRef[string, MongoConn[AsyncSocket]]
    tls: bool
    authenticated: bool
    db*: string
    writeConcern*: BsonDocument
    flags: QueryFlags
    readPreference*: ReadPreference
    retryableWrites*: bool
    compressions*: seq[CompressorId]
    query: TableRef[string, seq[string]]

  ReadPreference* {.pure.} = enum
    primary = "primary"
    primaryPreferred = "primaryPreferred"
    secondary = "secondary"
    secondaryPreferred = "secondaryPreferred"
    nearest = "nearest"

  SslInfo* = object
    ## SslInfo will handle information for connecting with SSL/TLS
    ## connection.
    keyfile*: string  ## Key file path
    certfile*: string ## Certificate file path
    when defined(ssl) or defined(nimdoc):
      protocol*: SslProtVersion ## The SSL/TLS protocol

  Database* {.multisock.} = ref object of RootObj
    ## Database holds the `Mongo<#Mongo>`_ data as ``db`` field.
    name*: string
    db*: Mongo[AsyncSocket]

  Collection* {.multisock.} = ref object
    ## Collection holds the `Database<#Database>`_
    ## data as ``db`` field.
    name*: string ## Collection name
    dbname: string ## Database name, easier than ``coll.db.name``
    db*: Database[AsyncSocket]

  Cursor* {.multisock.} = object
    ## An object that will short-lived in a handle to fetch more data
    ## with the same identifier. Usually used for find queries variant.
    id*: int64
    firstBatch*: seq[BsonDocument]
    nextBatch*: seq[BsonDocument]
    db*: Database[AsyncSocket]
    ns*: string

  Query* {.multisock.} = object
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
    collection*: Collection[AsyncSocket]
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
  
  GridFS*{.multisock.} = ref object
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
    files*: Collection[AsyncSocket]
    chunks*: Collection[AsyncSocket]
    chunkSize*: int32

  CommandKind* = enum
    ## CommandKind is used to recognize whether the command is write
    ## or read. This is used significantly in case of server selection
    ## for multihost connections.
    ckWrite
    ckRead

  MongoError* = object of CatchableError

  MultiUri* {.deprecated: "Use MongoUri instead".} = MongoUri

  MongoUri* = distinct string
    ## A special distinct uri string to support multihost uri connections.
    ## A single uri connection can rely using this too.

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

proc setSsl(m: Mongo[Multisock], sslinfo: SslInfo) =
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
    for host, server in m.servers:
      for i, c in server.pool.connections:
        when verbose: echo &"wrapping ssl socket {i} for {host}"
        ctx.wrapSocket c.socket
    m.tls = true

template raiseEnableSsl: untyped =
  raise newException(MongoError,
    "Need to enable SSL/TLS ('-d:ssl')")

proc handleSsl(m: Mongo[Multisock]) =
  var tbl = m.query
  proc setCertKey (s: var SslInfo, vals: seq[string]) =
    for kv in vals:
      let kvs = kv.split ':'
      if kvs[0].toLower == "certificate":
        s.certfile = decodeUrl kvs[1]
      elif kvs[0].toLower == "key":
        s.keyfile = decodeUrl kvs[1]
  var isSsl = if "ssl" in tbl: "ssl"
            elif "tls" in tbl: "tls"
            else: ""
  var connectSSL = if isSsl == "": false
                  else:
                    try: parseBool tbl[isSsl][0]
                    except ValueError: false

  if (m.tls or connectSsl) and not withSsl: raiseEnableSsl()
  when defined(ssl):
    let prot = if sslProtVersion == "": protSSLv23
               else: parseEnum[SslProtVersion](sslProtVersion)
    var newsslinfo = SSLInfo(protocol: prot)
  else:
    var newsslinfo = SSLInfo()
  if m.tls or connectSSL:
    # do nothing with empty key and certificate file if there's no
    # `tlsCertificateKeyFile` provided
    if "tlsCertificateKeyFile".toLower in tbl:
      newsslinfo.setCertKey tbl["tlsCertificateKeyFile".toLower]
    m.setSsl newsslinfo
  elif "tlsCertificateKeyFile".toLower in tbl:
    # implicitly connecting with SSL/TLS
    newsslinfo.setCertKey tbl["tlsCertificatekeyFile".toLower]
    m.setSsl newsslinfo

proc handleWriteConcern(m: Mongo[Multisock]) =
  var w = bson()
  if "w" in m.query and m.query["w"].len > 0:
    # "w" here can be a number or a string.
    let val = m.query["w"][0]
    if val.all isDigit:
      w["w"] = try: (parseInt val).toBson
               except ValueError: 1.toBson
    else:
      w["w"] = val
  if "j" in m.query and m.query["j"].len > 0:
    w["j"] = m.query["j"][0]
  if not w.isNil:
    m.writeConcern = w

proc checkTlsValidity(m: Mongo[Multisock]) =
  let tlsCertInval = ["tlsInsecure", "tlsAllowInvalidCertificates"]
  let tlsHostInval = ["tlsInsecure", "tlsAllowInvalidHostnames"]
  if tlsCertInval.allIt(it.toLower in m.query):
    raise newException(MongoError,
      &"""Can't have {tlsCertInval.join(" and ")}""")
  if tlsHostInval.allIt(it.toLower in m.query):
    raise newException(MongoError,
      &"""Can't have {tlsHostInval.join(" and ")}""")

proc newMongo*[S: Multisock](host = "localhost", port = 27017, master = true,
  poolconn = poolconn, sslinfo = SslInfo(), ssl = defined(ssl)): Mongo[S] =
  ## Give a new `Mongo<#Mongo>`_ instance manually from given parameters.
  result = Mongo[S](
    servers: newTable[string, MongoConn[S]](1),
    query: newTable[string, seq[string]](),
    readPreference: ReadPreference.primary
  )
  result.servers[&"{host}:{port}"] = MongoConn[S](
    isMaster: master,
    host: host,
    port: Port port,
    pool: initPool[S](poolconn)
  )
  if ssl:
    var sslinfo = sslinfo
    when defined(ssl):
      sslinfo.protocol = protSSLv23
    result.setSsl sslInfo

proc newMongo[S: Multisock](uri: seq[Uri], poolconn = poolconn, isTls = false): Mongo[S]
proc newMongo*[S: Multisock](muri: MongoUri, poolconn = poolconn, dnsserver = "8.8.8.8",
  dnsport = 53): Mongo[S] =
  ## Overload the newMongo for accepting raw uri string as MongoUri.
  # This is actually needed because Mongodb specify custom
  # definition by supporting multiple user:pass@host:port
  # format in domain host uri.

  template raiseInvalidSep: untyped =
    raise newException(MongoError,
      &"Whether invalid URI {uri} or missing trailing '/'")
    
  let uri = muri.string
  if uri.count('/') < 3:
    raiseInvalidSep()
  let uriobj = parseUri uri
  type URLUri = Uri
  var uris: seq[URLUri]
  if uriobj.scheme == "":
    raise newException(MongoError, &"No scheme protocol provided at \"{uri}\" uri")
  if uriobj.scheme notin ["mongodb", "mongo", "mongodb+srv", "mongo+srv"]:
    raise newException(MongoError,
      "Only supports mongodb:// or mongo:// or mongodb+srv:// or mongo+srv://, " &
        &"provided: \"{uriobj.scheme}\"")
  elif uriobj.scheme == "mongodb+srv" or uriobj.scheme == "mongo+srv":
    if not withSsl: raiseEnableSsl()
    let client = newDNSClient(server = dnsserver, port = dnsport)
    try:
      let resp = client.sendQuery(&"_mongodb._tcp.{uriobj.hostname}", SRV)
      uris = newseq[URLUri](resp.answers.len)
      if uris.len == 0:
        var errmsg = &"Dns cannot resolve the {uriobj.hostname}, " &
                     "check your internet connection"
        raise newException(MongoError, errmsg)
      for i, ans in resp.answers:
        let srvrec = ans as SRVRecord
        uris[i] = Uri(
          scheme: "mongodb",
          hostname: srvrec.target,
          port: $srvrec.port,
          username: uriobj.username,
          password: uriobj.password,
          query: uriobj.query,
          path: uriobj.path
        )
      result = newMongo[S](uris, poolconn, isTls = true)
      return
    except TimeoutError:
      let msg = &"Dns timeout when sending query to {uriobj.hostname} " &
                &", with dns server: {dnsserver}"
      raise newException(MongoError, msg)
    # reraise the uncaught exception
  let schemepos = uri.find("://")
  let scheme = uri[0..schemepos-1].toLowerAscii
  let trailingsep = uri.find('/', start = schemepos+3)
  if trailingsep == -1:
    raiseInvalidSep()
  let hosts = uri[schemepos+3 .. trailingsep-1].split(',')
  uris = newseq[URLUri](hosts.len)
  if hosts.len == 0:
    raise newException(MongoError, &"Unable to parse multihost URI '{uri}'")
  for i, host in hosts:
    var uname, pwd, hostname, port: string
    let splitdomain = host.split('@')
    var hostdompos = 0
    if splitdomain.len > 1:
      hostdompos = 1
      let upw = splitdomain[0].split(':')
      uname = upw[0]
      if upw.len > 1:
        pwd = upw[1]
    let hdom = splitdomain[hostdompos].split(':')
    if hdom.len > 1:
      port = hdom[1]
    hostname = hdom[0]
    uris[i] = Uri(
      scheme: scheme,
      hostname: hostname,
      port: port,
      username: uname,
      password: pwd,
      query: uriobj.query,
      path: uriobj.path
    )
  result = newMongo[S](uris, poolconn)

proc newMongo*[S: MultiSock](uri: Uri, poolconn = poolconn): Mongo[S] =
  ## Give a new `Mongo<#Mongo>`_ instance based on URI.
  result = newMongo[S](@[uri], poolconn)

proc newMongo[S: Multisock](uri: seq[Uri], poolconn = poolconn, isTls = false): Mongo[S] =
  result = Mongo[S](
    tls: isTls,
    servers: newTable[string, MongoConn[S]](uri.len.nextPowerOfTwo),
    query: decodeQuery(uri[0].query),
    readPreference: ReadPreference.primary
  )

  if uri[0].path != "":
    var paths = uri[0].path.split("/")
    if paths.len > 1:
      result.db = paths[1]

  for u in uri:
    let port = try: parseInt(u.port)
              except ValueError: 27017
    when verbose:
      dump port
    var hostport = &"{u.hostname}:{u.port}"
    result.servers[hostport] = MongoConn[S](
      host: u.hostname,
      port: Port port,
      username: u.username,
      password: u.password,
      pool: initPool[S](poolconn)
    )
  #if result.main.host == "": result.main.host = "localhost"

  # need elaborate handling for URI connect
  # ref:https://github.com/mongodb/specifications/blob/master/source/uri-options/uri-options.rst 

  result.handleWriteConcern

  if "appname" notin result.query:
    result.query["appname"] = @["Anonimongo driver client apps"]

  result.checkTlsValidity

  result.handleSsl

  if "readPreference".toLowerAscii in result.query:
    let rps = result.query["readPreference".toLowerAscii]
    if rps.len > 0:
      result.readPreference = parseEnum[ReadPreference](rps[0])

  if "retryablewrites" in result.query and result.query["retryablewrites"].len > 0:
    result.retryableWrites = try: parseBool result.query["retryablewrites"][0]
                             except ValueError: false

  if "compressors" in result.query and result.query["compressors"].len > 0:
    when verbose: dump result.query["compressors"]
    result.compressions = result.query["compressors"].mapIt(it.parseEnum[:CompressorId])
    when verbose: dump result.compressions

  if "authsource" in result.query and result.query["authsource"].len > 0 and
    result.db == "":
    result.db = result.query["authsource"][0]

proc tls*(m: Mongo): bool = m.tls
proc authenticated*(m: Mongo): bool = m.authenticated
proc authenticated*(m: MongoConn): bool = m.authenticated
proc host*(m: MongoConn): string = m.host
proc port*(m: MongoConn): Port = m.port
proc query*(m: Mongo): lent TableRef[string, seq[string]] =
  m.query
proc flags*(m: Mongo): QueryFlags = m.flags

proc pickAnyServer[T: MultiSock](m: Mongo[T], test: (string, int) -> bool = nil): MongoConn[T] =
  var res: MongoConn[T]
  for host{.inject.}, server{.inject.} in m.servers:
    #if `test`:
    if test == nil or (test != nil and test(host, server.pool.available.len)):
      res = server
  res

proc main*[T: MultiSock](m: Mongo[T]): MongoConn[T] =
  if m.primary == "":
    #result = m.pickAnyServer true
    result = m.pickAnyServer
  else:
    result = m.servers[m.primary]

proc mainPreferred*[T: MultiSock](m: Mongo[T]): MongoConn[T] =
  if m.primary == "":
    result = m.pickAnyServer
  elif m.servers[m.primary].pool.available.len > 0:
    result = m.servers[m.primary]
  else:
    result = m.pickAnyServer((host: string, num: int) => host != m.primary)

proc secondary*[T: MultiSock](m: Mongo[T]): MongoConn[T] =
  if m.primary == "":
    result = m.pickAnyServer
  else:
    result = m.pickAnyServer((host: string, num: int) => host != m.primary)

proc secondaryPreferred*[T: MultiSock](m: Mongo[T]): MongoConn[T] =
  if m.primary == "":
    result = m.pickAnyServer
  else:
    result = m.pickAnyServer((host: string, num: int) => host != m.primary and num > 0)
    if result == nil:
      result = m.servers[m.primary]

proc hasUserAuth*(m: Mongo): bool =
  m.main.username != "" and m.main.password != ""

proc bulkAuthenticate[T: SHA1Digest | SHA256Digest](bulk: seq[MongoConn[AsyncSocket]],
  user, pass, dbname: string): Future[bool]{.multisock.} =
  if bulk.len == 0: return true
  for conn in bulk:
    var user = user
    var pass = pass
    if (user == "" or pass == "") and (conn.username != "" and conn.password != ""):
      user = conn.username
      pass = conn.password

    if await conn.pool.authenticate(user, pass, T, dbname):
      result = true
      conn.authenticated = true
    else:
      echo &"Connection on {conn.host}:{conn.port.int} cannot authenticate"
      result = false

proc authenticate*[T: SHA1Digest | Sha256Digest](m: Mongo[AsyncSocket], user, pass: string):
  Future[bool] {.multisock.} =
  ## Authenticate Mongo with given username and password and delegate it to
  ## `pool.authenticate<pool.html#authenticate,Pool,string,string,typedesc,string>`_.
  let adm = if m.db != "": (m.db & ".$cmd") else: "admin.$cmd"
  result = await toSeq(m.servers.values).bulkAuthenticate[:T](user, pass, adm)
  m.authenticated = result

proc authenticate*[T: SHA1Digest | SHA256Digest](m: Mongo[AsyncSocket]):
  Future[bool] {.multisock.} =
  ## Authenticate Mongo with available username and password from
  ## `Mongo<#Mongo>`_ object and delegate it to
  ## `pool.authenticate<pool.html#authenticate,Pool,string,string,typedesc,string>`_.
  if m.main.username == "" or m.main.password == "":
    raise newException(MongoError, "username or password not available")
  result = await authenticate[T](m, m.main.username, m.main.password)

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

func username*(m: Mongo): string =
  m.main.username

proc tailableCursor*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to support TailableCursor
  m.flags.incl Flags.TailableCursor

proc noTailable*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to not support TailableCursor
  m.flags.excl Flags.TailableCursor

func isTailable*(m: Mongo): bool =
  ## Check whether `Mongo<#Mongo>`_ is tailable set
  Flags.TailableCursor in m.flags

proc slaveOk*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to support SlaveOk flag
  m.flags.incl Flags.SlaveOk

proc noSlave*(m: Mongo) =
  ## Set `Mongo<#Mongo>`_ to not support SlaveOk flag
  m.flags.excl Flags.SlaveOk

proc `[]`*[T: Multisock](m: Mongo[T], name: string): Database[T] =
  ## Give new Database from `Mongo<#Mongo>`_,
  ## expected to long-live object.
  new result
  result.db = m
  result.name = name

proc `[]`*[T: Multisock](dbase: Database[T], name: string): Collection[T] =
  ## Give new `Collection<#Collection>`_ from
  ## `Database<#Database>`_, expected to long-live object.
  new result
  result.name = name
  result.dbname = dbase.name
  result.db = dbase

proc dbname*(cur: Cursor): string = cur.ns.split('.', 1)[0]
  ## Get `Database<#Database>`_, name from Cursor.
proc collname*(cur: Cursor): string =
  ## Get `Collection<#Collection>`_ name from Cursor.
  let nssplit = cur.ns.split('.', 1)
  if nssplit.len > 1:
    result = nssplit[1]

proc close*(m: Mongo) =
  for _, serv in m.servers:
    close serv.pool

proc initQuery*[T: Multisock](query = bson(), collection: Collection[T] = nil,
  skip = 0'i32, limit = 0'i32, batchSize = 101'i32): Query[T] =
  ## Init `query<#Query>`_ to be used for next find.
  ## Apparently this should be used for Query Plan Cache
  ## however currently the lib still hasn't support that feature yet.
  result = Query[T](
    query: query,
    collection: collection,
    skip: skip,
    limit: limit,
    batchSize: batchSize)

proc toCursor*[S: MultiSock](b: BsonDocument): Cursor[S] =
  Cursor[S](
    id: b["id"],
    firstBatch: if "firstBatch" in b: b["firstBatch"].ofArray.map(ofEmbedded) else: @[],
    nextBatch: if "nextBatch" in b: b["nextBatch"].ofArray.map(ofEmbedded) else: @[],
    ns: b["ns"],
  )