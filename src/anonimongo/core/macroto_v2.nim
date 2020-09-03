import macros, sugar, strformat, strutils

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
    fieldDef: NimNode
    fieldImpl: NimNode
    distinctSyms: seq[NimNode]
    refnode: NimNode


template extractBracketFrom(n: NimNode): untyped =
  n.expectKind nnkBracketExpr
  n[1]

proc assignPrim(info: NodeInfo): NimNode =
  let
    fieldDef = info.fieldDef
    fieldname = fieldDef[0]
    fieldNameStr = newStrLitNode $fieldname
    typeIdent = ident("of" & ($info.fieldDef[1]).capitalizeAscii)
    resvar = info.resvar
    bsonObject = info.origin
    isref = info.refnode.kind != nnkEmpty
  let
    assignedNode =
      if isref:
        quote do:(`resvar`.`fieldname`[])
      else:
        quote do:(`resvar`.`fieldname`)
    bsonVal =
      if isref:
        quote do:(`bsonObject`[`fieldNameStr`].`typeIdent`)
      else:
        quote do:(`bsonObject`[`fieldNameStr`])
  if info.distinctSyms.len == 0:
    if isref:
      result = quote do:
        if `fieldNameStr` in `bsonObject`:
          new(`resvar`.`fieldname`)
          `assignedNode` = `bsonVal`
    else:
      result = quote do:
        if `fieldNameStr` in `bsonObject`:
          `assignedNode` = `bsonVal`
  else:
    let primRes = genSym(nskLet, "primRes")
    let primType = fieldDef[1]
    let distinctSym = info.distinctSyms[0]
    result = quote do:
      if `fieldNameStr` in `bsonObject`:
        let `primRes`:`primType` = `bsonObject`[`fieldNameStr`]
        `assignedNode` = `distinctSym`(`primRes`)

proc isPrimitive(node: NimNode): bool =
  node.kind == nnkSym and node.len == 0

proc isSymExported(node: NimNode): bool =
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

proc processDistinctAndRef(n: var NimNode, fieldType: NimNode):
  (NimNode, seq[NimNode]) =
  checknode fieldType
  result[0] = newEmptyNode()
  if n.kind == nnkDistinctTy:
    result[1].add fieldType
  dump result[1].len
  checknode n
  while n.kind in {nnkRefTy, nnkDistinctTy}:
    if n.kind == nnkRefTy:
      result[0] = n[0]
      result[1].add n[0]
    else:
      result[1].add n[0]
    n = n[0].getTypeImpl


template prepareWhenStmt(w: var NimNode, fieldtype, fieldname: NimNode,
  isref: NimNode, info: NodeInfo) =
  if isref.kind == nnkEmpty:
    let typeStr = "of" & ($fieldtype).capitalizeAscii
    let bsonVar = nnkBracketExpr.newTree(info.origin, fieldname)
    let callBsonVar = newCall(typestr, bsonVar)
    w.add nnkElifBranch.newTree(
        newCall("compiles", callBsonVar),
        newAssignment(info.resvar, callBsonVar))

template identDefsCheck(nodeBuilder: var NimNode, nodeInfo: NodeInfo,
  fielddef: NimNode) =

  checknode fielddef

  # preparing with various checkings
  fielddef.passIfIdentDefs
  var fieldname = fielddef[0]
  fieldname.passIfFieldExported
  fieldname.retrieveSym
  checknode fielddef
  let fieldtype = fielddef[1]
  var fieldTypeImpl = getTypeImpl fieldtype

  let (isref, distinctSyms) = fieldTypeImpl.processDistinctAndRef fieldType

  var newinfo = nodeInfo
  newinfo.distinctSyms = distinctSyms
  newinfo.refnode = isref

  var whenhead = nnkWhenStmt.newTree()
  whenhead.prepareWhenStmt(fieldType, fieldname, isref, nodeInfo)

  # checking the implementation
  var elseStmt = newStmtList()
  if fieldTypeImpl.isPrimitive:
    newinfo.fieldDef = nnkIdentDefs.newTree(fieldname, fieldTypeImpl,
      newEmptyNode())
    if distinctSyms.len > 1:
      elseStmt.add assignPrim(newinfo)
    else:
      elseStmt.add assignPrim(newinfo)
  elif fieldTypeImpl.kind == nnkObjectTy:
    newinfo.fieldImpl = fieldType.getImpl
    newinfo.fieldDef = nnkIdentDefs.newTree(fieldname, fieldtype, newEmptyNode())
    newinfo.resvar = nnkDotExpr.newTree(nodeInfo.resvar, fieldname)
    elseStmt.add assignObj(newinfo)
    discard
  else:
    echo fieldType.repr, " conversion is not available"
    checknode fieldTypeImpl
    checknode fieldType
    echo "==========="
  if whenhead.len > 0:
    whenhead.add nnkElse.newTree(elseStmt)
    nodeBuilder.add whenhead
  else:
    nodeBuilder.add elseStmt

proc assignObj(info: NodeInfo): NimNode =
  let
    resvar = genSym(nskVar, "objres")
    objty = info.fieldImpl[2]
    targetSym = info.fieldImpl[0]
    bsonVar = genSym(nskVar, "bsonVar")
    inforig = info.origin
    fieldstr = $info.fieldDef[0]
  result = newStmtList(
    quote do:( var `resvar` = `targetSym`() ),
    quote do:( var `bsonVar` =`inforig`[`fieldstr`].ofEmbedded )
  )
  var newinfo = info
  newinfo.resvar = resvar
  newinfo.origin = bsonVar
  let reclist = objty[2]
  for fielddef in reclist:
    identDefsCheck(result, newinfo, fielddef)
  let res = info.resvar
  result.add quote do:
    `res` = unown(`resvar`)

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
  #checknode result

template bsonExport*() {.pragma.}