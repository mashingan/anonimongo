import std/[jsffi, dom, jsconsole, sugar, asyncjs, strformat]
type
  WsObj = JsObject

proc fetch(url: cstring, opts: js): Future[js]{.importc, async.}
proc send(o: js): js {.importcpp.}
proc slice(o: js): js {.importcpp.}
# proc setTimeout(cb: proc(), timeout: cint) {.importc.}
proc newWebSocket(s: cstring): WsObj {.importcpp: "new WebSocket(@)".}
# proc WebSocket(s: cstring): WsObj = js()
proc onmessage(ws: WsObj, cb: proc(event: Event)) {.importcpp.}
proc onopen(ws: WsObj, cb: proc(event: Event)) {.importcpp.}
proc submitfile(): bool {.exportc: "submit_file".} =
  let
    ws = newWebSocket("ws://localhost:3000/ws-upload")
    # ws = jsNew WebSocket("ws://localhost:3000/ws-upload")
    filedom = document.querySelector("#input-field")
    spinner = document.querySelector(".lds-roller")
  ws.onmessage = (ev: Event) => (
    let data = ev.toJs.data
    console.log(data)
    let infonode = document.querySelector("#upload-info")
    var disableInfoNode = false
      
    if data.to(cstring) == "ok":
      spinner.style.display = "none"
      disableInfoNode = true
      infonode.style.display = "block"
      infonode.style.borderColor = "green"
      infonode.style.backgroundColor = "green"
      infonode.innerHTML = "Upload OK"
    elif data.to(cstring) == "error":
      infonode.innerHTML = "Upload Failed"
      spinner.style.display = "none"
      disableInfoNode = true
      infonode.style.display = "block"

    if disableInfoNode:
      discard setTimeout(
        () => (
          let infonode = document.querySelector("#upload-info")
          {.emit: "if (!`infonode`) { return; }".}
          infonode.style.display = "none"
          infonode.style.borderColor = "green"
          infonode.style.backgroundColor = "green"
        ), 5000
      )
  )

  ws.onopen = proc(_: Event) =
    spinner.style.display = "block"
    ws.send(filedom.toJs.files[0].name)
    ws.send(filedom.toJs.files[0].slice())
    ws.send("done".toJs)

  true

proc removeFile(filename, refid: cstring): Future[bool] {.exportc, async.} =
  let resp = await fetch(cstring fmt"/delete/{filename}",
    js{
      `method`: cstring "DELETE",
      mode: cstring "cors",
      cache: cstring "no-cache",
      credentials: cstring "same-origin"
    })
  if resp == nil:
    return false
  if resp.status.to(cint) == 200:
    let
      parentul = document.querySelector("#list-file")
      alink = document.querySelector(cstring fmt"#{refid}")
    parentul.removeChild(alink)
    console.log(cstring fmt"deleting {filename} is success")

  result = true