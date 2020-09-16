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
    isResDirect: bool
    isDirectOriginVar: bool
    bsonKey: string
  VariantInfo = object
    kind, targetEnum: NimNode


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

proc isSeq(n: NimNode): bool =
  n.expectKind nnkBracketExpr
  n.len == 2 and $n[0] == "seq"

proc isArray(n: NimNode): bool =
  n.expectKind nnkBracketExpr
  n.len == 3 and $n[0] == "array"

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
    fieldNameStr = if info.bsonKey == "": newStrLitNode $fieldname
                   else: newLit info.bsonKey
    resvar = info.resvar
    bsonObject = info.origin
    headif = if not info.isDirectOriginVar:
               quote do: `fieldNameStr` in `bsonObject`
             else:
               newLit true
    bsonVar = if not info.isDirectOriginVar:
                quote do: `bsonObject`[`fieldNameStr`]
              else: `bsonObject`

  var
    bodyif = info.parentSyms.buildBodyIf bsonVar
    asgnTgt  = if info.isResDirect:
                 quote do: `resvar`
               else:
                 quote do: `resvar`.`fieldname`

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
    if node[0].kind == nnkPostfix:
      result = true
      return
    else:
      for prg in node[1]:
        if prg.kind == nnkSym and $prg == "bsonExport":
          result = true
          break
  else:
    result = false

proc extractFieldName(node: NimNode): NimNode =
  if node.kind == nnkPostFix: result = node[1]
  elif node.kind == nnkPragmaExpr: result = node[0]
  else: result = newEmptyNode()
  if result.kind == nnkPostfix: result = result[1]

template passIfIdentDefs(n: NimNode) =
  if n.kind != nnkIdentDefs:
    when defined(verbose):
      echo "fielddef is not ident defs"
      checknode n
    continue

template passIfFieldExported(n: NimNode) =
  if not n.isSymExported:
    when defined(verbose): echo n.repr, " not exported"
    continue

template retrieveSym(n: var NimNode) =
  n = extractFieldName n
  if n.kind == nnkEmpty: continue

template extractBsonKey(n: NimNode): string =
  var r = ""
  if n.kind == nnkPragmaExpr and n.len > 0:
    for pragma in n[1]:
      if pragma.kind == nnkExprColonExpr and $pragma[0] == "bsonKey":
        r = $pragma[1]
        break
  r

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
    var typeStr = "of" & ($fieldtype).capitalizeAscii
    # special treatment for BsonDocument
    if typeStr == "ofBsonDocument":
      typeStr = "ofEmbedded"
    let fieldstrNode = if info.bsonKey != "": newLit info.bsonKey
                       else: newLit $fieldname
    let bsonVar =
      if not info.isDirectOriginVar:
        nnkBracketExpr.newTree(info.origin, fieldstrNode)
      else:
        info.origin
    let callBsonVar = newCall(typestr, bsonVar)
    let asgnVar = if not info.isResDirect: newDotExpr(info.resvar, fieldname)
                  else: info.resvar
    let headif = if info.isResDirect: newLit true
                 else: newCall("contains", info.origin, fieldstrNode)
    let ifthere = nnkIfStmt.newTree(
      nnkElifBranch.newTree(
        headif,
        newAssignment(asgnVar, callBsonVar)))
    w.add nnkElifBranch.newTree(
        newCall("compiles", callBsonVar),
        #newAssignment(asgnVar, callBsonVar))
        ifthere)

proc handleObjectVariant(info: NodeInfo): NimNode

template identDefsCheck(nodeBuilder: var NimNode, nodeInfo: NodeInfo,
  fdf: NimNode) =

  if fdf.kind == nnkNilLit:
    nodeBuilder.add quote do: discard
    continue
  var fieldname = fdf[0]
  if fdf.kind == nnkRecCase:
    fieldname = fieldname[0]
    fieldname.passIfFieldExported
  else:
    fieldname.passIfFieldExported

  if fdf.kind == nnkRecCase:
    var info = nodeInfo
    info.fieldDef = fdf
    nodeBuilder.add handleObjectVariant(info)
    continue

  let keystr = fieldname.extractBsonKey

  # preparing with various checkings
  fdf.passIfIdentDefs
  fieldname.retrieveSym
  let fieldtype = fdf[1]
  var fieldTypeImpl = getTypeImpl fieldtype

  let parentSyms = fieldTypeImpl.processDistinctAndRef fieldType

  var newinfo = nodeInfo
  newinfo.parentSyms = parentSyms
  newinfo.bsonKey = keystr

  var whenhead = nnkWhenStmt.newTree()
  whenhead.prepareWhenStmt(fieldType, fieldname, newinfo)

  newinfo.fieldDef = newIdentDefs(fieldname, fieldtype, newEmptyNode())
  newinfo.resvar = if not nodeInfo.isResDirect:
                     newDotExpr(nodeInfo.resvar, fieldname)
                   else: nodeInfo.resvar

  # checking the implementation
  var elseStmt = newStmtList()
  if fieldTypeImpl.isPrimitive:
    newinfo.fieldDef = nnkIdentDefs.newTree(fieldname, fieldTypeImpl,
      newEmptyNode())
    newinfo.isResDirect = true
    elseStmt.add assignPrim(newinfo)
  elif fieldTypeImpl.kind == nnkObjectTy:
    var fieldobj = fieldType
    if fieldobj.kind == nnkRefTy:
      fieldobj = fieldobj[0]
    elif fieldobj.kind == nnkBracketExpr:
      fieldobj = fieldobj[0]
    newinfo.fieldImpl = fieldobj.getImpl
    elseStmt.add assignObj(newinfo)
  elif fieldTypeImpl.kind == nnkBracketExpr:
    var fieldseq = fieldtype
    # handle when direct form of seq[Type] or array[N, Type]
    if fieldseq.kind != nnkBracketExpr:
      fieldseq = fieldseq.getImpl
      while fieldseq.kind in {nnkRefTy, nnkDistinctTy, nnkSym}:
        if fieldseq.kind != nnkSym: fieldseq = fieldseq[0].getImpl
        else: fieldseq = fieldseq.getImpl
    newinfo.fieldImpl = fieldseq
    elseStmt.add assignArr(newinfo)
  else:
    when defined(verbose):
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
  const refdist = {nnkRefTy, nnkDistinctTy}
  var
    lastImpl: NimNode
    lastTypeDef: NimNode
    placeholder = if fieldType.kind in refdist:
                    fieldType[0].getImpl
                  elif fieldType.kind == nnkBracketExpr:
                    fieldType[0].getImpl
                  else: fieldType.getImpl
  placeholder.expectKind nnkTypeDef
  while placeholder.kind == nnkTypeDef:
    let definition = placeholder[^1]
    lastTypeDef = placeholder
    if definition.kind in refdist:
      case definition[0].kind
      of nnkSym:
        placeholder = definition[0].getImpl
      of nnkObjectTy:
        lastImpl = definition[0]
        break
      of nnkBracketExpr:
        placeholder = definition[0][0].getImpl
      elif definition[0].kind in refdist:
        # handle when distinct ref TypeSymbol
        placeholder = definition[0][0].getImpl
    elif definition.kind == nnkObjectTy:
      lastImpl = definition
      break
    elif definition.kind == nnkBracketExpr:
      lastImpl = definition
      break
  if placeholder.kind == nnkNilLit and lastImpl == nil:
    lastImpl = lastTypeDef[^1]
    if lastImpl.kind in refdist:
      lastImpl = lastImpl[0]
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
    fieldstr = if info.bsonKey == "": $fieldname
               else: info.bsonKey
    origin = info.origin
    headif = if not info.isResDirect:
               quote do: `fieldstr` in `origin`
             else:
               newLit true
    (_, seqty) = if fieldtype.kind == nnkBracketExpr: (nil, fieldtype)
                 else: fieldtype.extractLastImpl
    bsonOrigin = if fieldstr == "dummy": origin
                 else: quote do: `origin`[`fieldstr`]
  
  var bodyif = newStmtList()
  bodyif.add quote do:
    var `seqvar`: `seqty`
  let
    arrayOp = if seqty.isArray: true else: false
    arrseqType = if arrayOp: seqty[2]
                 else: seqty[1]
    isBinary = arrseqType.kind == nnkSym and
               arrseqType.strVal.toLowerAscii in ["byte", "uint8"]
  
  if isBinary:
    bodyif.add quote do:
      `seqvar` = `bsonOrigin`.ofBinary
  else:
    bodyif.add quote do:
      var `bsonArr` = `bsonOrigin`.ofArray
    let
      theobj = genSym(nskVar, "arrseqobj")
      theval = if arrayOp: quote do: `bsonArr`[i]
              else: ident"bsonObj"
      fielddef = newIdentDefs(
        nnkPostFix.newTree(ident"*", ident"dummy"),
        arrseqType)
      newinfo = NodeInfo(
        origin: theval,
        resvar: theobj,
        fielddef: fielddef,
        isResDirect: true,
        isDirectOriginVar: true,
      )
    var forstmt = newNimNode nnkForStmt
    var forbody = newStmtList()
    if fieldtype.len == 3 or seqty.isArray:
      forstmt.add ident"i"
      forstmt.add quote do:
        0 .. min(`seqvar`.len, `bsonArr`.len) - 1
    elif fieldtype.len == 2 or seqty.isSeq:
      forstmt.add ident"bsonObj"
      forstmt.add bsonArr
    forbody.add quote do:
      var `theobj`: `arrseqType`
    for _ in 0 .. 0:
      identDefsCheck(forbody, newinfo, fielddef)
    if arrayOp:
      forbody.add quote do:
        `seqvar`[i] = `theobj`
    else:
      forbody.add quote do: `seqvar`.add `theobj`
    forstmt.add forbody
    bodyif.add forstmt

  let addbody = info.parentSyms.buildBodyIf(seqvar)
  bodyif.add addbody

  let target = info.resvar
  let lastIdent = if addbody.len > 1: addbody[^1].retrieveLastIdent
                  else: seqVar
  bodyif.add(quote do: `target` = unown(`lastIdent`))

  result = quote do:
    if `headif`: `bodyif`


template handleTable(n: NimNode, ops: untyped) =
  const tblname = ["Table", "TableRef"]
  if n.kind == nnkBracketExpr:
    case ($n[0])
    of "typeDesc":
      if n[1].kind == nnkSym and $n[1] in tblname:
        `ops`
      elif n[1].kind == nnkBracketExpr and $n[1][1] in tblname:
        `ops`
    of tblname:
      `ops`


proc processIfObjectVariant(n: NimNode): (bool, VariantInfo) =
  n.expectKind nnkRecList
  var isobjectVariant = false
  var variantKind, targetEnum: NimNode
  var variantKindStr: string
  for field in n: # check for object variant
    case field.kind
    of nnkEmpty: continue
    of nnkRecCase:
      isobjectVariant = true
      variantKind = field[0][0]
      if variantKind.kind == nnkPostfix: variantKind = variantKind[1]
      targetEnum = field[0][1]
      variantKindstr = $variantkind
      break
    else: discard
  result[0] = isobjectVariant
  result[1] = VariantInfo(
    kind: variantKind,
    targetEnum: targetEnum,
  )

proc assignObj(info: NodeInfo): NimNode =
  info.fieldDef[1].handleTable:
    return newEmptyNode()
  let
    resvar = genSym(nskVar, "objres")
    targetSym = info.fieldImpl[0]
    bsonVar = genSym(nskVar, "bsonVar")
    inforig = info.origin
    fieldstr = if info.bsonKey == "": $info.fieldDef[0]
               else: info.bsonkey
    fieldType = info.fieldDef[1]
    headif = if not info.isResDirect:
               quote do: `fieldstr` in `inforig`
             else: newLit true
    bsonOrig = if info.isResDirect: inforig
               else: quote do: `inforig`[`fieldstr`]
    (lastTypedef, objty) = fieldType.extractLastImpl
  var
    fieldImpl = getTypeImpl fieldType
    isDirect = false
    bsonSource = quote do:
      `bsonOrig`.ofEmbedded
  if $lastTypedef[0] == "Time":
    isDirect = true
    bsonSource = quote do:
      `bsonOrig`.ofTime
  elif $lastTypedef[0] == "Oid":
    isDirect = true
    bsonSource = quote do:
      `bsonOrig`.ofObjectId
  var bodyif = newStmtList(
    quote do:
      var `bsonVar` =`bsonSource`
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
      if isDirect: info.parentSyms.buildBodyIf(bsonVar, isObject = false)
      else: info.parentSyms[0..^2].buildBodyIf(resvar, isObject = false)
    lastIdent =
      if addBody.len > 0: addBody[^1].retrieveLastIdent
      else: resvar
  bodyif.add addBody
  let res = info.resvar
  bodyif.add(quote do: `res` = unown(`lastIdent`))
  result = quote do:
    if `headif`: `bodyif`

proc handleObjectVariant(info: NodeInfo): NimNode =
  info.fieldDef[0].expectKind nnkIdentDefs
  result = newStmtList()
  let variantKind = info.fieldDef[0][0].extractFieldName
  let resvar = info.resvar
  var casenode = nnkCaseStmt.newTree(quote do: `resvar`.`variantKind`)
  for casebody in info.fieldDef[1 .. ^1]:
    casebody.expectKind nnkOfBranch
    #casebody[0].expectKind nnkIntLit
    casebody[1].expectKind nnkRecList
    if casebody[1].len == 0:
      casenode.add nnkOfBranch.newTree(casebody[0],
        nnkDiscardStmt.newTree(newEmptyNode()))
      continue
    var caseof = nnkOfBranch.newTree(casebody[0], newEmptyNode())
    var casebodystmt = newStmtList()
    for identdefs in casebody[1]:
      identDefsCheck(casebodystmt, info, identdefs)
    caseof[1] = casebodystmt
    casenode.add caseof
  result.add casenode

macro to*(b: untyped, t: typed): untyped =
  ## Macro to is automatic conversion from symbol/variable BsonDocument
  ## to specified Type. This doesn't support dynamic values of array, only
  ## support homogeneous value-type array. It can convert only when the field
  ## is exported or using special pragma ``bsonExport`` to enable its conversion
  ## without exporting the field itself to other modules.
  ## 
  ## For custom type conversion, user can provide the ``proc``, ``func`` or ``converter``
  ## named with pattern of ``"of" & Type.name``. For example, the ``Type`` is ``SimpleObj``
  ## so the proc name is ``ofSimpleObj``. The complete example is shown below:
  ## 
  ## .. code-block:: Nim
  ##    import anonimongo/core/bson
  ##    type
  ##      Embedtion = object
  ##        embedfield*: int
  ##        embedstat*: string
  ##        wasProcInvoked: bool
  ##      SimpleEmbedObject = object
  ##        intfield*: int
  ##        strfield*: string
  ##        embed*: Embedtion
  ## 
  ##    proc ofEmbedtion(b: BsonBase): Embedtion =
  ##      let embed = b.ofEmbed
  ##      result.embedfield = embed["embedfield"]
  ##      result.embedstat = embed["embedstat"]
  ##      result.wasProcInvoked = true
  ## 
  ##    let bsimple = bson({
  ##      intfield: 42,
  ##      strfield: "that's 42",
  ##      embed: {
  ##        embedfield: 42,
  ##        embedstat: "42",
  ##      },
  ##    })
  ##    let simple = bsimple.to SimpleEmbedObject
  ##    doAssert simple.intfield == 42
  ##    doAssert simple.strfield == "that's 42"
  ##    doAssert simple.embed.embedfield == 42
  ##    doAssert simple.embed.embedstat == "42"
  ##    doAssert simple.embed.wasProcInvoked
  ## 
  ## Note that the ``ofType`` isn't checked for the outer most of Type because
  ## if user wants implement the specifics conversion, the user just can simply
  ## call it immediately without resorting to macro ``to``.
  ##
  let st = getType t
  st.handleTable:
    result = quote do: `t`()
    return

  let
    isRef = st[1].kind == nnkBracketExpr and st[1].len > 1
    typesym =
      if isRef and ':' in $st[1][1]:
        st[1][1]
      else: st[1]

    stTyDef = typesym.getImpl
    targetTypeSym = extractBracketFrom st
    targetImpl = stTyDef[2]
    reclist = if targetImpl.kind == nnkRefTy: targetImpl[0][2] else: targetImpl[2]
    resvar = genSym(nskVar, "res")

  var nodeInfo = NodeInfo(
    origin: b,
    target: t,
    resvar: resvar,
  )
  let (isobjectVariant, variantinfo) = reclist.processIfObjectVariant
  result = newStmtList()
  if not isobjectVariant:
    result.add quote do:
      var `resvar`: `targetTypeSym`
    if isRef:
      result.add quote do:
        new(`resvar`)
  else:
    let
      variantKind = variantinfo.kind
      targetEnum = variantinfo.targetEnum
      variantKindStr = $variantKind
    result.add(quote do:
      var `resvar` = `t`(`variantKind`: parseEnum[`targetEnum`](`b`[`variantKindStr`])))
  for fielddef in reclist:
    identDefsCheck(result, nodeInfo, fielddef)

  result.add(quote do: unown(`resvar`))
  #checknode result

template bsonExport*() {.pragma.}

template bsonKey*(key: string) {.pragma.}