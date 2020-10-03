import macros

template bsonifyCheckBody(val: NimNode) {.dirty.} =
  var objval: NimNode
  case val.kind
  of nnkNilLit:
    objval = quote do: bsonNull()
  of nnkTableConstr:
    objval = embedBson val
  of nnkBracket:
    objval = arrayBson val
  of nnkCurly:
    objval = quote do: bson({}).toBson
  else:
    objval = quote do: `val`.toBson

proc embedBson(p: NimNode): NimNode {.compiletime.}
proc arrayBson(p: NimNode): NimNode {.compiletime.} =
  p.expectKind nnkBracket
  var rr = newseq[NimNode]()
  for el in p:
    bsonifyCheckBody el
    rr.add objval
  result = newcall("bsonArray", rr)

proc embedBson(p: NimNode): NimNode {.compiletime.} =
  p.expectKind nnkTableConstr
  var rr = newseq[NimNode]()
  for el in p:
    let ident = $el[0]
    let val = el[1]
    bsonifyCheckBody val
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
    bsonifyCheckBody(val)
    result.add quote do:
      (`ident`, `objval`)