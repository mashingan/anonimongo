import macros, sugar, strformat

{.warning[UnusedImport]: off.}

template checknode(n: untyped): untyped {.used.} =
  dump `n`.kind
  dump `n`.len
  dump `n`.repr

template bsonExport*() {.pragma.}

template extractBracketFrom(n: NimNode): untyped =
  n.expectKind nnkBracketExpr
  n[1]

proc assignPrim(resvar, bsonObject, fieldname: NimNode): NimNode =
  let fieldNameStr = newStrLitNode $fieldname
  result = quote do:
    if `fieldNameStr` in `bsonObject`:
      `resvar`.`fieldname` = `bsonObject`[`fieldNameStr`]

proc isPrimitive(node: NimNode): bool =
  node.kind == nnkSym and node.len == 0

proc isSymExported(node: NimNode): bool =
  #node.expectKind nnkSym
  node.isExported# or node.hasCustomPragma(bsonExport)

template identDefsCheck(nodeBuilder: var NimNode, bsonObj, resvar, fielddef: NimNode) =
  #fielddef.expectKind nnkIdentDefs
  if fielddef.kind != nnkIdentDefs:
    echo "fielddef is not ident defs"
    checknode fielddef
  let fieldname = fielddef[0]
  if fieldname.kind != nnkSym or not fieldname.isSymExported:
    if fieldname.kind == nnkSym: echo $fieldname, " is not exported"
    checknode fieldname
    continue
  let fieldtype = fielddef[1]
  let fieldTypeImpl = getTypeImpl fieldtype
  if fieldTypeImpl.isPrimitive:
    echo $fieldType, " is primitive"
    nodeBuilder.add assignPrim(resvar, bsonObj, fieldname)
  else:
    #echo $fieldType, " is not primitive"
    discard

macro to*(b: untyped, t: typed): untyped =
  let st = getType t
  let targetTypeSym = extractBracketFrom st
  let targetImpl = getTypeImpl targetTypeSym
  let reclist = targetImpl[2]
  let resvar = genSym(nskVar, "res")
  checknode targetTypeSym
  result = newStmtList(
    quote do:(var `resvar` = `targetTypeSym`())
  )
  for fielddef in reclist:
    identDefsCheck(result, b, resvar, fielddef)

  result.add(quote do: unown(`resvar`))
  checknode result