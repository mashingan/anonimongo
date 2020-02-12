proc embedBson(p: NimNode): NimNode {.compiletime.}
proc arrayBson(p: NimNode): NimNode {.compiletime.} =
  assert p.kind == nnkBracket
  var rr = newseq[NimNode]()
  for el in p:
    var objval: NimNode
    if el.kind == nnkTableConstr:
      objval = embedBson el
    elif el.kind == nnkBracket:
      objval = arrayBson el
    else:
      objval = el
    let theval = objval
    rr.add theval
  result = newcall("bsonArray", rr)

proc embedBson(p: NimNode): NimNode {.compiletime.} =
  assert p.kind == nnkTableConstr
  var rr = newseq[NimNode]()
  for el in p:
    let ident = $el[0]
    let val = el[1]
    let objval = if val.kind == nnkTableConstr: embedBson val
                 elif val.kind == nnkBracket: arrayBson val
                 else: quote do: `val`.toBson
    rr.add quote do:
      (`ident`, `objval`)

  let br = newcall("newbson", rr)
  result = quote do:
    `br`.toBson

macro bson*(p: untyped): untyped =
  ## Macro for defining BsonDocument seamless as if
  ## it's an immediate object syntax supported by Nim.
  result = newcall("newbson")
  for el in p:
    let ident = $el[0]
    let val = el[1]
    var objval: NimNode
    if val.kind == nnkBracket:
      objval = arrayBson val
    elif val.kind == nnkTableConstr:
      objval = embedBson val
    else:
      objval = quote do: `val`.toBson
    result.add quote do:
      (`ident`, `objval`)
