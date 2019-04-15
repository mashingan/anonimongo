import wire, absonimpl
from sugar import dump

proc authenticate(sock: AsyncSocket) {.async.} =
  let q = bson(
    ("user", "readwrite".toBson),
    ("pwd", "readwrite".toBson)
  )
  dump q
  var s = newStringStream()
  discard s.prepareQuery(0, 0, opQuery.int32, 0, "reporting.$cmd",
    0, 1, q)
  await sock.send s.readAll
  discard await sock.getReply

when isMainModule:

  var socket = newAsyncSocket()
  waitFor socket.connect("localhost", Port 27017)

  #waitFor socket.authenticate
  waitFor socket.dropDatabase("newcoll.$cmd")

  close socket
