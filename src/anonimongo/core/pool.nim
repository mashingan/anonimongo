import deques, math, tables, strformat, sequtils
import sugar, options, times
import bson, wire, auth
import scram/client

{.warning[UnusedImport]: off.}

const verbose {.booldefine.} = false

type
  Connection* = object
    ## Connection is an object representation of a single
    ## asyncsocket and its identifier.
    socket*: AsyncSocket ## Socket which used for sending/receiving Bson.
    id*: int ## Identifier which used in pool for socket availability.

  Pool* = ref object
    ## A single ref object that will live as long Mongo ref-object lives.
    connections: TableRef[int, Connection] ## Actual pool for keeping connections.
    available*: Deque[int] ## The deque mechanism to indicate which\
      ## connection available.

proc connections*(p: Pool): lent TableRef[int, Connection] =
  ## Retrieve the connections table.
  p.connections

proc initConnection*(id = 0): Connection =
  ## Init for a connection.
  result.socket = newAsyncSocket()
  result.id = id

proc contains*(p: Pool, i: int): bool =
  ## Check whether the id available in connections.
  i in p.connections

proc `[]`*(p: Pool, i: int): Connection =
  ## Retrieve the i-th connection object in a pool.
  p.connections[i]

proc `[]=`*(p: Pool, i: int, c: Connection) =
  ## Set the i-th connection object with c.
  p.connections[i] = c

proc initPool*(size = 16): Pool =
  ## Init a pool. The size very likely higher than supplied
  ## pool size, because of deque need to be in size the power of 2.
  new result
  let realsize = nextPowerOfTwo size
  result.connections = newTable[int, Connection](realsize)
  result.available = initDeque[int](realsize)
  for i in 1 .. realsize:
    result[i] = i.initConnection
    result.available.addFirst i

proc getConn*(p: Pool): Future[(int, Connection)] {.async.} =
  ## Retrieve a random connection with its id in async. In case
  ## no available queues in the pool, it will poll whether any
  ## other connections will be available soon.
  while true:
    if p.available.len > 0:
      let id = p.available.popLast
      var conn = p.connections[id]
      #when not defined(release):
        #dump id
      result = (id, move conn)
      return
    else:
      try: poll(100)
      except ValueError: discard

proc connect*(p: Pool, address: string, port: int) {.async.} =
  ## Connect all connection to specified address and port.
  for i, c in p.connections:
    await c.socket.connect(address, Port port)
    when verbose:
      echo "connection: ", i, " is connected"

proc close*(p: Pool) =
  ## Close all connections in a pool.
  for _, c in p.connections:
      if not c.socket.isClosed:
        close c.socket
        when verbose:
          echo "connection: ", c.id, " is closed"

proc endConn*(p: Pool, i: Positive) =
  ## End a connection and return back the id to available queues.
  p.available.addFirst i.int

proc authenticate*(p: Pool, user, pass: string, T: typedesc = Sha256Digest,
  dbname = "admin.$cmd"): Future[bool] {.async.} =
  ## Authenticate all connections in a pool with supplied username,
  ## password, type which default to SHA256Digest, and database which
  ## default to "admin". Type receives SHA1Digest as other typedesc.
  ## Currently this taking too long for large pool connections.
  result = true
  var authops = newseq[Future[bool]](p.connections.len)
  when verbose:
    dump authops.len
    dump p.connections.len
  for i, c in p.connections:
    when verbose: echo &"conn {i} to auth."
    authops[i-1] = c.socket.authenticate(user, pass, T, dbname)
  if anyIt(await all(authops), not it):
    echo "Some connection failed to authenticate. Failed"
    result = false
  else:
    result = true

when isMainModule:

  proc dummy(pool: Pool, i: int) {.async.} =
    echo "spawning: ", i
    let (cid, conn) = await pool.getConn
    defer: pool.endConn cid
    await sleepAsync(200)
    echo "end conn: ", conn.id

  proc main {.async.} =
    let poolSize = 16
    let loopsize = poolsize * 3
    var pool = initPool(poolSize)

    let starttime = cpuTime()
    var ops = newseq[Future[void]](loopsize)
    for count in 0 ..< loopSize:
      #ops[count] = pool.toHandshake(count)
      ops[count] = pool.dummy(count)
    try:
      await all(ops)
    except:
      echo getCurrentExceptionMsg()
    when not defined(release):
      dump pool.available
    echo "ended loop at: ", cpuTime() - starttime

    close pool

  let start = cpuTime()
  waitFor main()
  echo "whole operation: ", cpuTime() - start
