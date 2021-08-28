when (compiles do: import karax / karaxdsl):
  import karax / [karaxdsl, vdom]
else:
  {.error: "Please use `logue extension karax` to install!".}


import std/[strformat, oids]
import ../types


proc makeList*(rows: seq[Entry]): string =
  let vnode = buildHtml(html):
    p: text "List items are as follows:"
    table(border = "1"):
      for row in rows:
        tr:
          td: a(href = fmt"/item/{row.id}"): text row.title
          td: text(if row.isTodo: "todo" else: "done")
          td: a(href = fmt"/edit/{row.id}"): text "Edit"
    p: a(href = "/new"): text "New Item"
  result = $vnode

proc editList*(id: Oid, title: string, isTodo = true): string =
  let vnode = buildHtml(html):
    p: text fmt"Edit the task with ID = {id}"
    form(action = fmt"/edit/{id}", `method` = "get"):
      input(`type` = "text", name = "task", value = title, size = "100",
          maxlength = "80")
      select(name = "status"):
        option: text "open"
        option: text "closed"
      br()
      input(`type` = "submit", name = "save", value = "save")
  result = $vnode

proc newList*(): string =
  let vnode = buildHtml(html):
    p: text "Add a new task to the ToDo list:"
    form(action = "/new", `method` = "get"):
      input(`type` = "text", size = "100", maxlength = "80", name = "task")
      input(`type` = "submit", name = "save", value = "save")
  result = $vnode


when isMainModule:
  # let t = makeList(@[@["1", "2", "3"], @["4", "6", "9"]])
  let t = makeList(@[
    Entry(id: genOid(), title: "test 1", isTodo: true),
    Entry(id: genOid(), title: "test 2", isTodo: true),
  ])
  # let e = editList(12, @["ok"])
  let e = editList(genOid(), title = "test edit")
  let n = newList()
  writeFile("todo.html", t)
  writeFile("edit.html", e)
  writeFile("new.html", n)
