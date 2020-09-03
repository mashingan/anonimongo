import macros, sugar, strformat

{.warning[UnusedImport]: off.}

template checknode(n: untyped): untyped {.used.} =
  dump `n`.kind
  dump `n`.len
  dump `n`.repr

type
  NodeInfo = object
    origin: NimNode
    target: NimNode
    resvar: NimNode
    fieldImpl: NimNode


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
  #node.isExported or node.hasCustomPragma(bsonExport)
  case node.kind
  of nnkPostFix:
    result = $node[0] == "*"
  of nnkPragmaExpr:
    for prg in node[1]:
      prg.expectKind nnkSym
      if $prg == "bsonExport":
        result = true
        break
  else:
    result = false

proc extractFieldName(node: NimNode): NimNode =
  if node.kind == nnkPostFix: result = node[1]
  elif node.kind == nnkPragmaExpr: result = node[0]
  else: result = newEmptyNode()

template passIfIdentDefs(n: NimNode) =
  if n.kind != nnkIdentDefs:
    echo "fielddef is not ident defs"
    checknode n
    continue

template passIfFieldExported(n: NimNode) =
  if not n.isSymExported:
    echo n.repr, " not exported"
    continue

template retrieveSym(n: var NimNode) =
  n = extractFieldName n
  if n.kind == nnkEmpty: continue

template identDefsCheck(nodeBuilder: var NimNode, nodeInfo: NodeInfo,
  fielddef: NimNode) =
  fielddef.passIfIdentDefs
  var fieldname = fielddef[0]
  fieldname.passIfFieldExported
  fieldname.retrieveSym
  let fieldtype = fielddef[1]
  let fieldTypeImpl = getTypeImpl fieldtype
  if fieldTypeImpl.isPrimitive:
    echo $fieldType, " is primitive"
    checknode fieldtype
    echo fieldTypeImpl.repr, " is primitive"
    checknode fieldTypeImpl
    nodeBuilder.add assignPrim(nodeInfo.resvar, nodeInfo.origin, fieldname)
  else:
    echo fieldType.repr, " is not primitive"
    checknode fieldTypeImpl
    checknode fieldType
    discard

macro to*(b: untyped, t: typed): untyped =
  let
    st = getType t
    stTyDef = st[1].getImpl
    targetTypeSym = extractBracketFrom st
    targetImpl = stTyDef[2]
    reclist = targetImpl[2]
    resvar = genSym(nskVar, "res")
  result = newStmtList(
    quote do:(var `resvar` = `targetTypeSym`())
  )
  var nodeInfo = NodeInfo(
    origin: b,
    target: t,
    resvar: resvar,
  )
  for fielddef in reclist:
    identDefsCheck(result, nodeInfo, fielddef)

  result.add(quote do: unown(`resvar`))
  checknode result