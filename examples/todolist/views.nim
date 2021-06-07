import prologue
import anonimongo
import std/[strformat, strutils, oids, os, sugar]

import ./templates/basic
import types

let
  appName = getEnv("appName", "Todolist app")
  mongo = newMongo(
    MongoUri fmt"mongodb://rootuser:rootpass@mongodb:27017/admin&appName={appName}",
    poolconn = 8,
  )

var connectSuccess = false
block tryconnect:
  for _ in 1..3:
    try:
      if not waitFor mongo.connect:
        echo "cannot connect to mongo"
        continue
      if not waitfor mongo.authenticate[:SHA1Digest]:
        echo "cannot authenticate"
        continue
      connectSuccess = true
      break tryconnect
    except:
      echo getCurrentExceptionMsg()
      sleep 5_000 # wait for 5 seconds

if not connectSuccess:
  quit "Tried 3 times to connect, all failed"

var
  dbm = mongo["todolist"]
  todocoll = dbm["todo"]
if (waitfor todocoll.count()) == 0:
  let wr = waitfor todocoll.insert(@[
    bson { title: "Nim lang", isTodo: false },
    bson { title: "Prologue web framework", isTodo: true },
    bson { title: "Let's start studying Prologue web framework", isTodo: true },
    bson { title: "My favorite web framework", isTodo: true },
  ])
  if not wr.success:
    echo wr.reason

proc todoList*(ctx: Context) {.async, gcsafe.} =
  var rows = newSeq[Entry]()
  for row in await todocoll.findIter():
    rows.add(row.to Entry)
  resp htmlResponse(makeList(rows=rows))

proc newItem*(ctx: Context) {.async, gcsafe.} =
  if ctx.getQueryParams("save").len != 0:
    let row = ctx.getQueryParams("task").strip
    let id = genOid()
    discard await todocoll.insert(@[
      bson { "_id": id, title: row, isTodo: true }
    ])
    resp htmlResponse(fmt"<p>The new task was inserted into the database, the ID is {id}</p><a href=/>Back to list</a>")
  else:
    resp htmlResponse(newList())

proc editItem*(ctx: Context) {.async, gcsafe.} =
  if ctx.getQueryParams("save").len != 0:
    let
      edit = ctx.getQueryParams("task").strip
      status = ctx.getQueryParams("status").strip
      id = ctx.getPathParams("id", "")
    var statusId = false
    dump status
    dump id
    if status == "open":
        statusId = true
    let oid = parseOid id.cstring
    let qset = bson { "$set": {
        title: edit,
        isTodo: statusId
    }}
    dump qset
    dump oid
    let wr = await todocoll.update(
      bson { "_id": oid },
      qset,
    )
    dump wr
    if not wr.success or wr.n == 0:
      resp htmlResponse(fmt"""<p>The item number {id} was failed updated: reason "{wr.reason}" """ &
        "</p><a href=/>Back to list</a>")
    else:
      resp htmlResponse(fmt"<p>The item number {id} was successfully updated</p><a href=/>Back to list</a>")
  else:
    let
      id = parseOid ctx.getPathParams("id", "").cstring
      task: string = try: (await todocoll.findOne(bson { "_id": id }))["title"] except: ""
    resp htmlResponse(editList(id, task))

proc showItem*(ctx: Context) {.async, gcsafe.} =
  let
    item = ctx.getPathParams("item", "")
    task = try: await todocoll.findOne(bson { "_id": parseOid item.cstring }) except: bson()
  dump item
  let home_link = """<a href="/">Back to list</a>"""
  if task.isNil:
    resp "This item number does not exist!" & home_link
  else:
    let
      tasktitle = task["title"].ofString
      status = block:
        if not task["isTodo"].ofBool:
          "Done"
        else:
          "Doing"
    resp fmt"Task: {taskTitle}<br/>Status: {status}</br>" & home_link
