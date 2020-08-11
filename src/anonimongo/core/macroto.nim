const objtyp = {nnkObjectTy, nnkRefTy}

proc ifIn(jn: NimNode): NimNode =
  if jn.kind == nnkBracketExpr:
    let obj = jn[0]
    if jn[1].kind == nnkStrLit:
      let keyname = $jn[1]
      result = quote do:
        `keyname` in `obj`
    else:
      result = newLit true
  else:
    result = newLit true

proc isSeq(n: NimNode): bool {.compiletime.} =
  n.expectKind nnkBracketExpr
  n.len == 2

proc isArray(n: NimNode): bool {.compiletime.} =
  n.expectKind nnkBracketExpr
  n.len == 3

proc isSeqByte(n: NimNode): bool =
  n.isSeq and n[1].kind == nnkSym and $n[1] == "byte"

proc isIt(node: NimNode, it: string): bool {.compiletime.} =
  node.kind == nnkSym and $node == it

proc isTime(node: NimNode): bool {.compiletime.} =
  node.isIt "Time"

proc isBsonDocument(node: NimNode): bool {.compiletime.} =
  node.isIt "BsonDocument"

proc getImpl(n: NimNode): NimNode {.compiletime.} =
  if n.kind == nnkSym:
    result = n.getTypeImpl
  elif n.kind == nnkRefTy:
    result = n[0].getTypeImpl
  elif n.kind == nnkBracketExpr:
    if n.isSeq:
      result = n[1].getTypeImpl
    elif n.isArray:
      result = n[2].getTypeImpl
    else:
      result = newEmptyNode()
  else:
    result = newEmptyNode()

proc isPrimitive(fimpl: NimNode): bool {.compiletime.} =
  fimpl.kind == nnkSym and fimpl.len == 0

proc primAssign(thevar, jn, identdef: NimNode, direct = false): NimNode {.compiletime.} =
  let fieldstr = newStrLitNode $identdef[0]
  let fieldacc = identdef[0]
  let dotexpr =
    if not direct:
      quote do: `thevar`.`fieldacc`
    else:
      thevar
  result = quote do:(
    if `fieldstr` in `jn`:
      `dotexpr` = `jn`[`fieldstr`])

proc primDistinct(thevar, jn, fld, impl: NimNode): NimNode {.compiletime.} =
  let newident = newIdentDefs(fld[0], impl)
  let tempres = gensym(nskVar, "primtemp")
  result = quote do:(var `tempres`: `impl`)
  result.add primAssign(tempres, jn, newident, direct = true)
  let distinctName = fld[1]
  result.add quote do: `thevar` = unown(`distinctName`(move(`tempres`)))

proc timeAssign(thevar, jn, fld: NimNode, distTy = newEmptyNode()):
  NimNode {.compiletime.} =
  let
    isDistinct = distTy.kind != nnkEmpty
    testif = ifIn jn
    resvar = genSym(nskVar, "timeres")
  var bodyif = newStmtList()
  if not isDistinct:
    let timetyp = fld[1]
    bodyif.add(quote do:
      var `resvar`: `timetyp` = `jn`
      `thevar` = unown(`resvar`)
    )
  else:
    let implTy = distTy[0]
    let distinctTy = fld[1]
    bodyif.add(quote do:
      var `resvar`: `implTy` = `jn`
      `thevar` = unown(`distinctTy`(`resvar`))
    )

  result = quote do:
    if `testif`: `bodyif`

template arrObjField(acc, fldready: untyped): untyped =
  let fldvar {.inject.} = gensym(nskVar, "field")
  let fimpl = fldready.getImpl
  var forbody {.inject.} = newStmtList(
    nnkVarSection.newTree(newIdentDefs(fldvar, fldready))
  )
  let objnode = objAssign(
    fldvar,
    acc,
    newIdentDefs(ident"", fldready),
    fimpl
  )
  forbody.add objnode

template arrPrimDistinct(dty, idn, finalizer: untyped): untyped =
  let arrbody {.inject.} = newStmtList(
    newNimNode(nnkVarSection).add(
      newIdentDefs(ident"tmp", dty[0], idn)),
    finalizer)

proc objAssign(thevar, jn, fld, fielddef: NimNode, distTy = newEmptyNode()):
    NimNode {.compiletime.}
proc arrAssign(thevar, jn, fld, fielddef: NimNode, distTy = newEmptyNode()):
    NimNode {.compiletime.} =
  fld[1].expectKind nnkBracketExpr
  let isDistinct {.used.} = distTy.kind == nnkDistinctTy
  let resvar = genSym(nskVar, "arrres")
  let testif = ifIn jn
  
  var bodyif = newStmtList()
  if fld[1].isSeqByte:
    bodyif.add newAssignment(thevar, newcall("ofBinary", jn))
  elif fld[1].isSeq:
    let fieldtype = fld[1]
    bodyif.add(quote do:
      var `resvar`: `fieldtype`)
    var seqfor = newNimNode(nnkForStmt).add(
      ident"obj", newDotExpr(jn, ident"ofArray"))
    if fielddef.kind in objtyp:
      if isDistinct:
        arrObjField(ident"obj", distTy[0])
        let distinctType = fld[1][1]
        forbody.add quote do: add(`resvar`, `distinctType`(move(`fldvar`)))
        seqfor.add forbody
      elif fld[1][1].isBsonDocument:
        seqfor.add quote do: add(`resvar`, obj.ofEmbedded)
      elif fld[1][1].isTime:
        seqfor.add quote do: add(`resvar`, obj)
      else:
        arrObjField(ident"obj", fld[1][1])
        forbody.add quote do: add(`resvar`, move(`fldvar`))
        seqfor.add forbody
    elif fielddef.isPrimitive:
      if not isDistinct:
        seqfor.add newCall("add", resvar, ident"obj")
      else:
        arrPrimDistinct(distTy, ident"obj",
          newCall("add", resvar, newCall(
            $fld[1][1], newCall("move", ident"tmp")
          )))
        seqfor.add arrbody
    bodyif.add seqfor
    bodyif.add quote do: `thevar` = unown(`resvar`)
  elif fld[1].isArray:
    let arrobj = ident "arrobj"
    bodyif.add(quote do:
      let
        `arrobj` = `jn`.ofArray)
    var arrfor = newNimNode(nnkForStmt).add(
      ident"i",
      newNimNode(nnkInfix).add(
        ident"..<",
        newIntLitNode(0),
        newCall("min", newCall("len", arrobj), newCall("len", thevar))
    ))
    if fielddef.kind in objtyp:
      if isDistinct:
        arrObjField(nnkBracketExpr.newTree(arrobj, ident"i"), distTy[0])
        let distinctType = fld[1][2]
        forbody.add quote do: `thevar`[i] = `distinctType`(`fldvar`)
        arrfor.add forbody
      else:
        arrObjField(nnkBracketExpr.newTree(arrobj, ident"i"), fld[1][2])
        forbody.add quote do: `thevar`[i] = `fldvar`
        arrfor.add forbody
    elif fielddef.isPrimitive:
      if not isDistinct:
        arrfor.add quote do: `thevar`[i] = `arrobj`[i]
      else:
        let distinctType = fld[1][2]
        arrPrimDistinct(distTy,
          (quote do: `arrobj`[i]),
          (quote do: `thevar`[i] = `distinctType`(move(tmp)))
        )
        arrfor.add arrbody
    bodyif.add arrfor
  result = quote do:
    if `testif`: `bodyif`

proc objAssign(thevar, jn, fld, fielddef: NimNode, distTy = newEmptyNode()):
    NimNode {.compiletime.} =
  let
    isDistinct = distTy.kind != nnkEmpty
    testif = ifIn jn
    jnobj = gensym(nskVar, "jnobj")
    resvar = genSym(nskVar, "objres")
    identresvar = if isDistinct: newIdentDefs(resvar, distTy[0])
                  else: newIdentDefs(resvar, fld[1])
  var bodyif = newStmtList()
  bodyif.add(newNimNode(nnkVarSection).add(
    identresvar,
    newIdentDefs(jnobj, newEmptyNode(), jn))
  )
  if fielddef.kind == nnkRefTy or fld[1].kind == nnkRefTy or
      (isDistinct and distTy[0].kind == nnkRefTy):
    bodyif.add(newCall("new", resvar))
  var reclist: NimNode
  if fielddef.kind == nnkObjectTy:
    reclist = fielddef[2]
  elif fielddef.kind == nnkRefTy:
    let tmp = fielddef[0].getImpl
    tmp.expectKind nnkObjectTy
    reclist = tmp[2]
  for field in reclist:
    if field.kind == nnkEmpty: continue
    let fimpl = field[1].getImpl
    let resfield = newDotExpr(resvar, field[0])
    if field[1].kind == nnkBracketExpr:
      if $field[1][0] in ["TableRef", "Deque"]:
        bodyif.add newEmptyNode()
        continue
      let fieldname = field[0]
      let jnfieldstr = fieldname.strval.newStrLitNode
      let jnfield = quote do: `jnobj`[`jnfieldstr`]
      let arr = arrAssign(resfield, jnfield, field, fimpl)
      bodyif.add arr
    elif fimpl.isPrimitive or field[1].isTime or field[1].isBsonDocument:
      bodyif.add primAssign(resvar, jnobj, field)
    elif fimpl.kind in objtyp:
      let jnfieldstr = field[0].strval.newStrLitNode
      let jnfield = quote do: `jnobj`[`jnfieldstr`]
      bodyif.add objAssign(resfield, jnfield, field, fimpl)
  if isDistinct:
    let fldist = fld[1]
    bodyif.add(quote do:
      `thevar` = unown(`fldist`(`resvar`)))
  else:
    bodyif.add(quote do: `thevar` = unown(`resvar`))
  result = quote do:
    if `testif`: `bodyif`

template identDefsCheck(result: var NimNode, resvar, field: NimNode,
  b, t: untyped): untyped =
  case field.kind
  of nnkEmpty: continue
  of nnkRecCase:
    result.add handleObjectVariant(resvar, field, b, t)
    continue
  else: discard
  let fimpl = field[1].getImpl
  let resfield = newDotExpr(resvar, field[0])
  let nodefield = newNimNode(nnkBracketExpr).add(b, newStrLitNode $field[0])
  if field[1].kind == nnkBracketExpr:
    let jnfieldstr = newStrLitNode $field[0]
    let jnfield = newNimNode(nnkBracketExpr).add(b, jnfieldstr)
    if fimpl.kind == nnkDistinctTy:
      let actimpl = fimpl[0].getImpl
      result.add arrAssign(resfield, jnfield, field, actimpl, fimpl)
    else:
      result.add arrAssign(resfield, jnfield, field, fimpl)
  elif field[1].isTime:
    result.add timeAssign(resfield, nodefield, field)
  elif field[1].isBsonDocument:
    result.add primAssign(resvar, b, field)
  elif fimpl.isPrimitive:
    result.add primAssign(resvar, b, field)
  elif fimpl.kind in objtyp:
    let resobj = objAssign(resfield, nodefield, field, fimpl)
    result.add resobj
  elif fimpl.kind == nnkDistinctTy:
    let distinctimpl = fimpl[0].getImpl
    if distinctimpl.isPrimitive:
      result.add primDistinct(resfield, b, field, distinctimpl)
    elif distinctimpl.kind in objtyp:
      if fimpl[0].isTime:
        result.add timeAssign(resfield, nodefield, field, fimpl)
      else:
        result.add objAssign(resfield, nodefield, field, distinctimpl, fimpl)
  else:
    # temporary placeholder
    checknode field[1]

proc handleObjectVariant(res, field, bobj, t: NimNode): NimNode =
  field[0].expectKind nnkIdentDefs
  result = newStmtList()
  let variantKind = field[0][0]
  var casenode = nnkCaseStmt.newTree(quote do: `res`.`variantKind`)
  for casebody in field[1 .. ^1]:
    casebody.expectKind nnkOfBranch
    casebody[0].expectKind nnkIntLit
    casebody[1].expectKind nnkRecList
    if casebody[1].len == 0:
      casenode.add nnkOfBranch.newTree(casebody[0],
        nnkDiscardStmt.newTree(newEmptyNode()))
      continue
    var caseof = nnkOfBranch.newTree(casebody[0], newEmptyNode())
    var casebodystmt = newStmtList()
    for identdefs in casebody[1]:
      identDefsCheck(casebodystmt, res, identdefs, bobj, t)
    caseof[1] = casebodystmt
    casenode.add caseof
  result.add casenode

template ignoreTable(st: NimNode) =
  if st[1].kind == nnkSym and st[1].strval in ["Table", "Deque"]:
    return quote do: `t`()
  elif st[1].kind == nnkBracketExpr and st[1][1].strval in ["Table", "Deque"]:
    return quote do: `t`()

macro to*(b: untyped, t: typed): untyped =
  ## Macro to is automatic conversion from symbol/variable BsonDocument
  ## to specified Type. This doesn't support dynamic values of array, only
  ## support homogeneous value-type array.
  ##
  runnableExamples:
    type MyFlatObject = object
      intfield: int
      strfield: string
      strarr: seq[string]
      documents: seq[BsonDocument]
    let bobj = bson({
       intfield: 1,
       strfield: "str",
       strarr: ["elm1", "elm2", "elm3"],
       documents: [
         { field1: 1, arbitrary: "fine" },
         { dynamic: true, field2: 2 },
         { phi: 3.14, field3: "nice" }
       ]
    })
    let flatobj = bobj.to MyFlatObject
    doAssert flatobj.documents.len == 3
    doAssert flatobj.intfield == 1
    doAssert flatobj.strarr[1] == "elm2"
    doAssert flatobj.documents[0]["field1"] == 1
    doAssert flatobj.documents[1]["dynamic"].ofBool

  let st = getType t
  st.ignoreTable
  result = newStmtList()
  let resvar = genSym(nskVar, "res")
  let stimpl = st[1].getTypeImpl
  var isref = false
  var reclist: NimNode
  if stimpl.kind != nnkRefTy:
    reclist = stimpl[2]
  else:
    result.add newCall("new", resvar)
    isref = true
    let tempimpl = stimpl[0].getTypeImpl
    reclist = tempimpl[2]
  var isobjectVariant = false
  var variantKind, targetEnum: NimNode
  var variantKindStr: string
  for field in reclist: # check for object variant
    case field.kind
    of nnkEmpty: continue
    of nnkRecCase:
      isobjectVariant = true
      variantKind = field[0][0]
      targetEnum = field[0][1]
      variantKindstr = $variantkind
      break
    else: discard
  if not isobjectVariant:
    result.add newNimNode(nnkVarSection).add(
      newIdentDefs(resvar, st[1]))
  else:
    result.add(quote do:
      var `resvar` = `t`(`variantKind`: parseEnum[`targetEnum`](`b`[`variantKindStr`])))
  for field in reclist:
    identDefsCheck(result, resvar, field, b, t)
  result.add(newCall("unown", resvar))
  #checknode result