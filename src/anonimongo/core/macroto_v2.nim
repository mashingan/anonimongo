import macros, sugar, strformat, strutils

{.warning[UnusedImport]: off.}

template checknode(n: untyped): untyped {.used.} =
  echo "==node=="
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
    parentSyms: seq[NimNode]


template checkinfo (n: NodeInfo) {.used.} =
  echo "==info=="
  for k, v in n.fieldPairs:
    dump k
    dump v.repr

template extractBracketFrom(n: NimNode): untyped =
  n.expectKind nnkBracketExpr
  n[1]

template retrieveLastIdent(n: NimNode): NimNode =
  var r: NimNode
  if n.kind == nnkStmtList:
    r = n[^1][1]
  elif n.kind == nnkVarSection:
    r = n[0][0]
  r

proc buildBodyIf(parents: seq[NimNode], bsonVar: NimNode,
  isObject = false): NimNode =
  var bodyif = newStmtList()
  var isPrevNodeDistinct = false
  for i in countdown(parents.len-1, 0):
    let parent = parents[i]
    let tempvar = genSym(nskVar, "tempvar")
    if parent.kind == nnkRefTy and bodyif.len > 0:
      let lastIdent = retrieveLastIdent bodyif[^1]
      let tempval =
        if bodyif[^1].kind == nnkVarSection:
          let parentSym = parent[0]
          (quote do: move(`parentSym`(`lastIdent`)))
        else:
          (quote do: move(`lastIdent`))
      bodyif.add quote do:
        var `tempvar`: `parent`
        new(`tempvar`)
        `tempvar`[] = `tempval`
    elif parent.kind == nnkRefTy:
      bodyif.add quote do:
        var `tempvar`: `parent`
        new(`tempvar`)
        `tempvar`[] = `bsonVar`
    elif parent.kind == nnkDistinctTy and bodyif.len > 0:
      let lastIdent = bodyif[^1].retrieveLastIdent
      let parentSym = parent[0]
      bodyif.add quote do:
        var `tempvar` = move(`parentSym`(`lastIdent`))
      isPrevNodeDistinct = true
    elif parent.kind == nnkDistinctTy:
      let parentSym = parent[0]
      bodyif.add quote do:
        var `tempvar` = `parentSym`(`bsonVar`)
    elif parent.kind == nnkSym and bodyif.len > 0:
      let lastIdent = bodyif[^1].retrieveLastIdent
      bodyif.add quote do:
        var `tempvar` = move(`parent`(`lastIdent`))
      isPrevNodeDistinct = true
    elif parent.kind == nnkSym and not isObject:
      bodyif.add quote do:
        var `tempvar` = `parent`(`bsonVar`)
  result = bodyif

proc assignPrim(info: NodeInfo): NimNode =
  let
    fieldDef = info.fieldDef
    fieldname = fieldDef[0]
    fieldNameStr = newStrLitNode $fieldname
    resvar = info.resvar
    bsonObject = info.origin
    headif = quote do: `fieldNameStr` in `bsonObject`
    bsonVar = quote do: `bsonObject`[`fieldNameStr`]

  var
    bodyif = info.parentSyms.buildBodyIf bsonVar
    asgnTgt  = quote do: `resvar`.`fieldname`

  if bodyif.len == 0:
    bodyif.add nnkDiscardStmt.newTree(newEmptyNode())
  elif bodyif.len > 0:
    let lastIdent = bodyif[^1].retrieveLastIdent
    bodyif.add quote do: `asgnTgt` = `lastIdent`
  result = quote do:
    if `headif`:`bodyif`

proc isPrimitive(node: NimNode): bool =
  node.kind == nnkSym and node.len == 0

proc isSymExported(node: NimNode): bool =
  case node.kind
  of nnkPostFix:
    result = true
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
  seq[NimNode] =
  const drefty = {nnkRefTy, nnkDistinctTy}
  if fieldtype.kind in drefty or fieldtype.kind == nnkSym:
    result.add fieldtype
  while n.kind in drefty:
    if n notin result:
      result.add n
    n = n[0].getTypeImpl

template prepareWhenStmt(w: var NimNode, fieldtype, fieldname: NimNode,
  info: NodeInfo) =
  if fieldtype.kind notin {nnkRefTy, nnkBracketExpr}:
    let typeStr = "of" & ($fieldtype).capitalizeAscii
    let fieldstrNode = newLit $fieldname
    let bsonVar = nnkBracketExpr.newTree(info.origin, fieldstrNode)
    let callBsonVar = newCall(typestr, bsonVar)
    let asgnVar = newDotExpr(info.resvar, fieldname)
    let ifthere = nnkIfStmt.newTree(
      nnkElifBranch.newTree(
        newCall("contains", info.origin, fieldstrNode),
        newAssignment(asgnVar, callBsonVar)))
    w.add nnkElifBranch.newTree(
        newCall("compiles", callBsonVar),
        #newAssignment(asgnVar, callBsonVar))
        ifthere)

template identDefsCheck(nodeBuilder: var NimNode, nodeInfo: NodeInfo,
  fielddef: NimNode) =

  # preparing with various checkings
  fielddef.passIfIdentDefs
  var fieldname = fielddef[0]
  fieldname.passIfFieldExported
  fieldname.retrieveSym
  let fieldtype = fielddef[1]
  var fieldTypeImpl = getTypeImpl fieldtype

  let parentSyms = fieldTypeImpl.processDistinctAndRef fieldType

  var newinfo = nodeInfo
  newinfo.parentSyms = parentSyms

  var whenhead = nnkWhenStmt.newTree()
  whenhead.prepareWhenStmt(fieldType, fieldname, newinfo)

  newinfo.fieldDef = newIdentDefs(fieldname, fieldtype, newEmptyNode())
  newinfo.resvar = newDotExpr(nodeInfo.resvar, fieldname)

  # checking the implementation
  var elseStmt = newStmtList()
  if fieldTypeImpl.isPrimitive:
    newinfo.fieldDef = nnkIdentDefs.newTree(fieldname, fieldTypeImpl,
      newEmptyNode())
    elseStmt.add assignPrim(newinfo)
  elif fieldTypeImpl.kind == nnkObjectTy:
    var fieldobj = fieldType
    if fieldobj.kind == nnkRefTy:
      fieldobj = fieldobj[0]
    newinfo.fieldImpl = fieldobj.getImpl
    elseStmt.add assignObj(newinfo)
  elif fieldTypeImpl.kind == nnkBracketExpr:
    var fieldseq = fieldtype
    while fieldseq.kind in {nnkRefTy, nnkDistinctTy}:
      fieldseq = fieldseq[0].getImpl
    newinfo.fieldImpl = fieldseq
    elseStmt.add assignArr(newinfo)
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

template extractLastImpl(fieldType: NimNode): (NimNode, NimNode) =
  var
    lastImpl: NimNode
    lastTypeDef: NimNode
    placeholder = if fieldType.kind in {nnkRefTy, nnkDistinctTy}:
                    fieldType[0].getImpl
                  else: fieldType.getImpl
  placeholder.expectKind nnkTypeDef
  while placeholder.kind == nnkTypeDef:
    let definition = placeholder[^1]
    lastTypeDef = placeholder
    if definition.kind in {nnkRefTy, nnkDistinctTy}:
      placeholder = definition[0].getImpl
    elif definition.kind == nnkObjectTy:
      lastImpl = definition
      break
  (lastTypedef, lastImpl)

proc isRefOrSymRef(parents: seq[NimNode]): bool =
  if parents.len > 1:
    let parent = parents[^1]
    if parent.kind == nnkRefTy:
      result = true
    elif parent.kind == nnkSym and
      parent.getTypeImpl.kind == nnkRefTy:
        result = true

proc assignObj(info: NodeInfo): NimNode

proc assignArr(info: NodeInfo): NimNode =
  let
    fieldname = info.fieldDef[0]
    fieldtype = info.fieldDef[1]
    bsonArr = genSym(nskVar, "bsonArr")
    seqvar = genSym(nskVar, "seqvar")
    fieldstr = $fieldname
    origin = info.origin
    headif = quote do: `fieldstr` in `origin`
    #(lastTypedef, seqty) = fieldtype.extractLastImpl
  var bodyif = newStmtList()
  #if fieldtype.kind in {nnkBracketExpr, nnkSym}:
  bodyif.add quote do:
    var `seqvar`: `fieldtype`
    var `bsonArr` = `origin`[`fieldstr`].ofArray
  var forstmt = newNimNode nnkForStmt
  if fieldtype.len == 3:
    forstmt.add ident"i"
    forstmt.add quote do:
      0 .. min(`seqvar`.len, `bsonArr`.len) - 1
    forstmt.add quote do:
      `seqvar`[i] = `bsonArr`[i]
  elif fieldtype.len == 2:
    forstmt.add ident"bsonObj"
    forstmt.add bsonArr
    forstmt.add(quote do: `seqvar`.add bsonObj)
  bodyif.add forstmt

  let target = info.resvar
  bodyif.add(quote do: `target` = unown(`seqvar`))

  result = quote do:
    if `headif`: `bodyif`

proc assignObj(info: NodeInfo): NimNode =
  let
    resvar = genSym(nskVar, "objres")
    targetSym = info.fieldImpl[0]
    bsonVar = genSym(nskVar, "bsonVar")
    inforig = info.origin
    fieldstr = $info.fieldDef[0]
    fieldType = info.fieldDef[1]
    headif = quote do: `fieldstr` in `inforig`
    (lastTypedef, objty) = fieldType.extractLastImpl
  var
    bodyif = newStmtList()
    fieldImpl = getTypeImpl fieldType
    isTime = false
  if $lastTypedef[0] == "Time":
    isTime = true
    bodyif = newStmtList(
      quote do:
        var `bsonVar` =`inforig`[`fieldstr`].ofTime
    )
  else:
    bodyif = newStmtList(
      quote do:
        var `bsonVar` =`inforig`[`fieldstr`].ofEmbedded
    )
  if info.parentSyms.isRefOrSymRef or fieldType.kind == nnkRefTy:
    let firstParent = info.parentSyms[^1]
    bodyif.add quote do:
      var `resvar`:`firstParent`
      new(`resvar`)
  elif info.parentSyms.len > 1:
    let immediateParent = info.parentSyms[^1]
    let parentSym =
      if immediateParent.kind == nnkDistinctTy:
        immediateParent[0]
      else: immediateParent
    bodyif.add quote do:
      var `resvar`: `parentSym`
  else:
    bodyif.add quote do:
      var `resvar`: `targetSym`
  var newinfo = NodeInfo(
    resvar: resvar,
    origin: bsonVar,
    parentSyms: fieldImpl.processDistinctAndRef fieldType,
    fieldImpl: lastTypedef
  )

  let reclist = objty[2]
  for fielddef in reclist:
    identDefsCheck(bodyif, newinfo, fielddef)
  let
    addBody =
      if isTime: info.parentSyms.buildBodyIf(bsonVar, isObject = true)
      else: info.parentSyms[0..^2].buildBodyIf(resvar, isObject = true)
    lastIdent =
      if addBody.len > 1: addBody[^1].retrieveLastIdent
      else: resvar
  bodyif.add addBody
  let res = info.resvar
  bodyif.add(quote do: `res` = unown(`lastIdent`))
  result = quote do:
    if `headif`: `bodyif`

macro to*(b: untyped, t: typed): untyped =
  let
    st = getType t
    stTyDef = st[1].getImpl
    targetTypeSym = extractBracketFrom st
    targetImpl = stTyDef[2]
    reclist = targetImpl[2]
    resvar = genSym(nskVar, "res")
  result = newStmtList(
    quote do:
      var `resvar`: `targetTypeSym`
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