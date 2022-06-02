import std/[os, asyncfile, asyncdispatch, asyncstreams, streams, strformat]
from std/sugar import dump
from std/strutils import parseInt
from std/uri import decodeUrl
import jester, ws, ws/jester_extra
import anonimongo, anonimongo/core/[pool, multisock]
import karax/[karaxdsl, vdom]

let
  appName = getEnv("appName", "Upload Grid FS")
  portApp = Port(try: parseInt(getEnv("port", "3000")) except: 3000)
  mongo = newMongo[Socket](
    MongoUri fmt"mongodb://rootuser:rootpass@mongodb:27017/admin?appName={appName}",
    # MongoUri fmt"mongodb://localhost:27017/admin?appName={appName}",
    poolconn = 8,
  )

settings:
  port = portApp

var connectSuccess = false
block tryconnect:
  for _ in 1..3:
    try:
      if not mongo.connect:
        echo "cannot connect to mongo"
        continue
      if not mongo.authenticate[:SHA1Digest]:
        echo "cannot authenticate"
        continue
      connectSuccess = true
      break tryconnect
    except:
      echo getCurrentExceptionMsg()
      sleep 1_000 # wait for 5 seconds

if not connectSuccess:
  quit "Cannot connect mongo, quit!", QuitFailure

#var grid = waitfor mongo["newtemptest"].createBucket()
var grid = mongo["temptest"].getBucket()
#var wr = waitfor grid.uploadFile(filename)

template kxi: int = 0
template addEventHandler(n: VNode; k: EventKind; action: string; kxi: int) =
  n.setAttr($k, action)

proc generateList: Future[VNode] {.async.} =
  result = buildHtml(tdiv):
    script(src="/js/appjs.js")
    ul(id="list-file"):
      for i, fname in grid.listFileNames:
        let linkhref = fmt"""http://localhost:{$portApp.int}/play/{fname}"""
        let idnum = fmt"id-{$i}"
        li(id=fmt"{idnum}"):
          a(href=linkhref): text fname
          a(href="#", onclick=fmt"removeFile('{fname}','{idnum}')"): text "[-]"

    a(href="/upload.html"): text "Upload new file"

# proc generatePlayer(fname: string): VNode =
#   discard

proc recheckAndReconnect(g: GridFS[AsyncSocket]): Future[void] {.multisock.} =
  let _ = mongo.connect
  let _ = mongo.authenticate[:SHA1Digest]
  # for k, mongoconn in g.files.db.mongo.servers.mpairs:
  # for k, mongoconn in g.files.db.db.servers.mpairs:
  #   for id, conn in mongoconn.pool.connections.mpairs:
  #     if conn.socket.isClosed:
  #       conn = Connection(
  #         socket: newAsyncSocket(),
  #         id: id,
  #       )


routes:
  get "/":
    redirect uri("/list")
  get "/list":
    resp $(await generateList())
    # resp Http404, "List is not available yet"
#   get "/":
#     resp Http200, """
# <!doctype html>
# <html lang="en">
# <head>
# <meta charset="utf-8">
# <title>Title</title>
# <script>
# function playvideo() {
#   let ws = new WebSocket("ws://localhost:3000/fma3.mkv");
#   var v = document.querySelector("#player");
# }
# </script>
# </head>
# <body>
#   <video id="player" width="1280" height="720">
#     <source src="http://localhost:3000/fma3.mkv" type="video/mp4">
#   </video>
#   <input type="button" onclick="playvideo();" value="Play">
# </body>
# </html>"""

  get "/play/@sendfile":
    enableRawMode()
    var gs: GridStream[Socket]
    try:
      gs = grid.getStream(decodeUrl @"sendfile")
      dump gs.fileSize
      var curread = 0
      let metadata = gs.metadata
      let mime: string = if not metadata.isNil and
                            "mime" in metadata:
                            metadata["mime"]
                         else: "video/mp4"
      request.sendHeaders(Http200, @[
        ("Content-Type", mime),
        ("Content-Length", &"{gs.fileSize}")
      ])
      while curread < gs.fileSize:
        var data = gs.read(1500.kilobytes)
        # dump gs.getPosition
        curread += data.len
        # dump curread
        request.send(data)
        #await sleepAsync(100)

    except IOError:
      let ioerrmsg = getCurrentExceptionMsg()
      # asyncCheck(recheckAndReconnect grid)
      recheckAndReconnect grid
      dump ioerrmsg
    except:
      let excmsg = getCurrentExceptionMsg()
      dump excmsg
    finally:
      if gs != nil:
        close gs
      # close request

 # get "/live":
  #   await response.sendHeaders()
  #   for i in 0 .. 10:
  #     await response.send("The number is: " & $i & "</br>")
  #     await sleepAsync(1000)
  #   response.client.close()
  # get "/close":
  #   resp Http200, "Server exiting, good bye!"
  #   quitapp()
  get "/ws-upload":
    echo "in ws-upload"
    var wsconn = await newWebSocket(request)
    try:
      await wsconn.send("send the filename")
      var fname = await wsconn.receiveStrPacket()
      var f = openAsync(fname, fmWrite)
      while wsconn.readyState == Open:
        let (op, seqbyte) = await wsconn.receivePacket()
        if op == Text:
          let msg = $seqbyte
          if msg == "done":
            await wsconn.send("ok")
            break
        if op == Binary:
          # resp Http400, "invalid sent format"
          # wsconn.close()
          # return
          var cnt = 0
          if seqbyte.len < 4096:
            await f.write seqbyte.join
            continue

          while cnt < (seqbyte.len-4096):
            let datastr = seqbyte[cnt .. cnt+4095].join
            cnt.inc 4096
            await f.write(datastr)
        await wsconn.send("ok")

      # wsconn.close()
      f.close()
      # discard await grid.uploadFile(fname)
      discard grid.uploadFile(fname)
      removeFile fname
    except:
      await wsconn.send("error")
      echo "websocket close: ", getCurrentExceptionMsg()
    resp Http200, "file uploaded"
  delete "/delete/@filename":
    let fname = decodeUrl @"filename"
    let matcher = bson { filename: fname }
    let wr = grid.removeFile(matcher, one = true)
    if not wr.success:
      resp Http500, wr.reason
      return
    resp Http200, fmt"{fname} is successfully deleted"