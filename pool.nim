import deques, math, tables, threadpool
import bson, wire

type
  Connection = object
    socket: AsyncSocket
    id: uint
  Pool = ref object
    connections: TableRef[int, Connection]
    available: Deque[int]
    connCount: int
    #event: SelectEvent
    #selector: Selector

proc initConnection(id = 0): Connection =
  result.socket = newAsyncSocket()
  result.id = id.uint

proc contains*(p: Pool, i: int): bool =
  i in p.connections

proc `[]`(p: Pool, i: int): Connection =
  p.connections[i]

proc `[]=`(p: Pool, i: int, c: Connection) =
  p.connections[i] = c

proc initPool(size = 16): Pool =
  new result
  result.connections = newTable[int, Connection](size)
  for i in 0 ..< 16:
    result[i] = i.initConnection

  result.available = initDeque[int](size.nextPowerOfTwo)
  #[
  result.event = newSelectEvent()
  result.selector = newSelector[bool]()

  result.selector.registerEvent(result.event, true)
  ]#

proc getConn(p: Pool): Future[Connection] =
  result = newFuture[Connection]("pool.getConn")
  proc retrieveConn(thepool: Pool): Future[Connection] {.async.} =
    while thepool.available.len == 0:
      discard sleepAsync 10

    return thepool[thepool.available.popFirst]

  try:
    let conn = p.retrieveConn
    p.connCount = (p.connCount + 1) mod p.connections.len
    result = p.retrieveConn
  except Exception as exc:
    result.fail exc

proc connect(p: Pool, address: string, port: int) {.async.} =
  #var conn = newseq[Future[void]](p.connections.len)
  for i, c in p.connections:
    await c.socket.connect(address, Port port)
    echo "connection: ", i, " is connected"

proc close(p: Pool) =
  for _, c in p.connections:
    if not c.socket.isClosed:
      close c.socket
      echo "connection: ", c.id, " is closed"

proc endConn(p: Pool, i: Positive) =
  p.available.addLast i.int

proc handshake(s: AsyncSocket, db: string) {.async.} =
  let q = bson({
    application: { name: "test connection pool" },
    driver: {
      name: "anonimongo - nim mongo driver",
      version: "0.0.4",
    },
    os: {
      "type": "Windows",
      architecture: "amd64"
    }
  })
  var stream = newStringStream()
  discard stream.prepareQuery(0, 0, opQuery.int32, 0, db,
    0, 1, q)
  await s.send stream.readAll
  look(await s.getReply)

when isMainModule:
  let poolSize = 16
  var pool = initPool(poolSize)
  waitFor pool.connect("localhost", 27017)

  proc toHandshake() {.gcsafe, async.} =
      var conn = await pool.getConn
      await conn.socket.handshake("reporting.$cmd")
      echo "end conn: ", conn.id
      pool.endConn conn.id

  for _ in 1 .. poolSize*2:
    discard(spawn toHandShake())

  sync()
  close pool
