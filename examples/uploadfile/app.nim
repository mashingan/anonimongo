import std/[os, asyncfile, asyncdispatch, asyncstreams, streams, strformat]
from std/sugar import dump
from std/strutils import parseInt
import jester, ws, ws/jester_extra
import anonimongo
import karax/[karaxdsl, vdom]

let
  appName = getEnv("appName", "Upload Grid FS")
  portApp = Port(try: parseInt(getEnv("port", "3000")) except: 3000)
  mongo = newMongo(
    MongoUri fmt"mongodb://rootuser:rootpass@localhost:27017/admin?appName={appName}",
    # MongoUri fmt"mongodb://localhost:27017/temptest&appName={appName}",
    poolconn = 8,
  )

settings:
  port = portApp

var connectSuccess = false
block tryconnect:
  for _ in 1..3:
    try:
      if not waitFor mongo.connect:
        echo "cannot connect to mongo"
        continue
      # if not waitfor mongo.authenticate[:SHA1Digest]:
      #   echo "cannot authenticate"
      #   continue
      connectSuccess = true
      break tryconnect
    except:
      echo getCurrentExceptionMsg()
      sleep 5_000 # wait for 5 seconds

#var grid = waitfor mongo["newtemptest"].createBucket()
var grid = waitfor mongo["temptest"].getBucket()
#var wr = waitfor grid.uploadFile(filename)

proc generateList: Future[VNode] {.async.} =
  result = buildHtml(ul):
    for fname in await grid.listFileNames:
      let linkhref = fmt"""http://localhost:{$portApp.int}/play/{fname}"""
      li:
        a(href=linkhref): text fname

proc generatePlayer(fname: string): VNode =
  discard

routes:
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

  get "/play/@videofile":
    #await request.sendHeaders(newHttpHeaders([
    #  ("Content-Type", "video/mkv")]))
    try:
      var gs = await grid.getStream(@"videofile")
      defer: close gs
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
        var data = await gs.read(1500.kilobytes)
        dump gs.getPosition
        curread += data.len
        dump curread
        request.send(data)
        await sleepAsync(100)

      resp Http200, "ok"
    except:
      let excmsg = getCurrentExceptionMsg()
      dump excmsg
      resp Http500, excmsg
    #request.client.close()
    #close request
    #var native = request.getNativeReq
    #close native.client
    #break route

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
    try:
      var wsconn = await newWebSocket(request)
      await wsconn.send("send the filename")
      var fname = await wsconn.receiveStrPacket()
      var f = openAsync(fname, fmWrite)
      while wsconn.readyState == Open:
        let (op, seqbyte) = await wsconn.receivePacket()
        if op != Binary:
          resp Http400, "invalid sent format"
          wsconn.close()
          return
        var cnt = 0
        if seqbyte.len < 4096:
          await f.write seqbyte.join
          continue

        while cnt < (seqbyte.len-4096):
          let datastr = seqbyte[cnt .. cnt+4095].join
          cnt.inc 4096
          await f.write(datastr)

        wsconn.close()
      f.close()
      discard await grid.uploadFile(fname)
    except:
      echo "websocket close: ", getCurrentExceptionMsg()
    resp Http200, "file uploaded"

  # post "/upload":
  #   echo "in upload"
  #   var f: AsyncFile
  #   var fstream = newFutureStream[string]("routes.upload")
  #   try:
  #     f = openAsync("uploaded.file", fmWrite)
  #   except IOError:
  #     echo getCurrentExceptionMsg()
  #     resp Http500, "Cannot upload file"
  #     return
  #   echo "ready to write"
  #   var datastream = newStringStream(request.formData.getOrDefault("file").body)
  #   # var asyncwrite = f.writeFromStream(fstream)
  #   while not datastream.atEnd:
  #     # read each of 500 bytes
  #     let strdata = datastream.readStr(1024 * 1024)
  #     echo strdata.len
  #     await fstream.write strdata
  #   fstream.complete
  #   resp Http200, "uploaded"
