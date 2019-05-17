import deques, math, tables, selectors
import sugar, options, locks, times
import bson, wire

type
  Connection* = object
    socket* {.guard: lock.}: AsyncSocket
    id*: uint
    lock*: Lock

  Pool* = ref object
    connections: TableRef[int, Connection]
    available*: Deque[int]
    event: SelectEvent
    selector: Selector[bool]

template withLock*(l, ops: untyped): untyped =
  {.locks: [l.lock].}:
    ops

proc initConnection*(id = 0): Connection =
  initLock result.lock
  withLock result:
    result.socket = newAsyncSocket()
  result.id = id.uint

proc contains*(p: Pool, i: int): bool =
  i in p.connections

proc `[]`*(p: Pool, i: int): Connection =
  p.connections[i]

proc `[]=`*(p: Pool, i: int, c: Connection) =
  p.connections[i] = c

proc initPool*(size = 16): Pool =
  new result
  result.connections = newTable[int, Connection](size)
  result.available = initDeque[int](size.nextPowerOfTwo)
  for i in 0 ..< size:
    result[i] = i.initConnection
    result.available.addFirst i

  result.event = newSelectEvent()
  result.selector = newSelector[bool]()
  result.selector.registerEvent(result.event, true)

proc getConn*(p: Pool): Future[Connection] {.async.} =
  while true:
    if p.available.len != 0:
      let id = p.available.popFirst
      return p.connections[id]
    else:
      try: poll(100)
      except ValueError: discard

proc connect*(p: Pool, address: string, port: int) {.async.} =
  for i, c in p.connections:
    withLock c:
      await c.socket.connect(address, Port port)
    echo "connection: ", i, " is connected"

proc close*(p: Pool) =
  for _, c in p.connections:
    withLock c:
      if not c.socket.isClosed:
        close c.socket
        echo "connection: ", c.id, " is closed"

proc endConn*(p: Pool, i: Positive) =
  p.available.addLast i.int

when isMainModule:

  proc query1(s: AsyncSocket, db: string, id: int32) {.async.} =
    look(await queryAck(s, id, db, "reporter", limit = 1))

  #[
  proc handshake(s: AsyncSocket, db: string, id: int32) {.async.} =
    let q = bson({
      isMaster: 1,
      client: {
        application: { name: "test connection pool: " & $id },
        driver: {
          name: "anonimongo - nim mongo driver",
          version: "0.0.4",
        },
        os: {
          "type": "Windows",
          architecture: "amd64"
        }
      }
    })
    echo "Handshake id: ", id
    dump q
    var stream = newStringStream()
    discard stream.prepareQuery(id, 0, opQuery.int32, 0, db,
      0, 1, q)
    await s.send stream.readAll
    look(await s.getReply)
    ]#

  let poolSize = 16
  let loopsize = poolsize * 3
  var pool = initPool(poolSize)
  waitFor pool.connect("localhost", 27017)

  proc toHandshake(i: int) {.async.} =
    echo "spawning: ", i
    let conn = await pool.getConn
    withLock conn:
      await conn.socket.query1("reporting", conn.id.int32)
    echo "end conn: ", conn.id
    pool.endConn conn.id

  let starttime = cpuTime()
  var count = 0
  var ops = newseq[Future[void]]()
  while count < loopSize:
    ops.add toHandshake(count)
    inc count
  waitFor all(ops)
  echo "ended loop at: ", cpuTime() - starttime

  close pool
