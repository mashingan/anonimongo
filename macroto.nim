
proc isSeq(n: NimNode): bool {.compiletime.} =
  n.expectKind nnkBracketExpr
  n.len == 2

proc isArray(n: NimNode): bool {.compiletime.} =
  n.expectKind nnkBracketExpr
  n.len == 3

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

# node helper check
template checknode(n: untyped): untyped {.used.} =
  dump `n`.kind
  dump `n`.len
  dump `n`.repr

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
  result = quote do:
    if `fieldstr` in `jn`:
      `dotexpr` = `jn`[`fieldstr`].get

proc primDistinct(thevar, jn, fld, impl: NimNode): NimNode {.compiletime.} =
  var newident = newIdentDefs(fld[0], impl)
  var tempres = gensym(nskVar, "primtemp")
  result = newStmtList(
    newNimNode(nnkVarSection).add(newIdentDefs(tempres, impl))
  )
  result.add primAssign(tempres, jn, newident, direct = true)
  result.add newAssignment(thevar, newCall("unown", newCall($fld[1],
    newCall("move", tempres))))

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
    finalizer
    )

proc objAssign(thevar, jn, fld, fielddef: NimNode, distTy = newEmptyNode()):
    NimNode {.compiletime.}
proc arrAssign(thevar, jn, fld, fielddef: NimNode, distTy = newEmptyNode()):
    NimNode {.compiletime.} =
  fld[1].expectKind nnkBracketExpr
  let isDistinct {.used.} = distTy.kind == nnkDistinctTy
  let resvar = genSym(nskVar, "arrres")
  let testif = newCall("isSome", jn)
  
  var bodyif = newStmtList()
  if fld[1].isSeq:
    bodyif.add nnkVarSection.newTree(newIdentDefs(resvar, fld[1]))
    var seqfor = newNimNode(nnkForStmt).add(
      ident"obj", newDotExpr(newCall("get", jn), ident"ofArray"))
    if fielddef.kind in {nnkObjectTy, nnkRefTy}:
      if isDistinct:
        arrObjField(ident"obj", distTy[0])
        forbody.add newCall("add", resvar, newCall(
          $fld[1][1], newCall("move", fldvar)
        ))
        seqfor.add forbody
      else:
        arrObjField(ident"obj", fld[1][1])
        forbody.add newCall("add", resvar, newCall("move", fldvar))
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
    bodyif.add newAssignment(thevar, newCall("unown", resvar))
  elif fld[1].isArray:
    let arrobj = ident "arrobj"
    bodyif.add newNimNode(nnkLetSection).add(
      newIdentDefs(arrobj, newEmptyNode(), newDotExpr(newCall("get", jn), ident"ofArray"))
    )
    var arrfor = newNimNode(nnkForStmt).add(
      ident"i",
      newNimNode(nnkInfix).add(
        ident"..<",
        newIntLitNode(0),
        newCall("min", newCall("len", arrobj), newCall("len", thevar))
    ))
    if fielddef.kind in {nnkObjectTy, nnkRefTy}:
      if isDistinct:
        arrObjField(nnkBracketExpr.newTree(arrobj, ident"i"), distTy[0])
        forbody.add newAssignment(
          nnkBracketExpr.newTree(thevar, ident"i"),
          newCall($fld[1][2], fldvar)
        )
        arrfor.add forbody
      else:
        arrObjField(nnkBracketExpr.newTree(arrobj, ident"i"), fld[1][2])
        forbody.add newAssignment(nnkBracketExpr.newTree(thevar, ident"i"), fldvar)
        arrfor.add forbody
    elif fielddef.isPrimitive:
      if not isDistinct:
        arrfor.add newAssignment(
          newNimNode(nnkBracketExpr).add(thevar, ident"i"),
          newNimNode(nnkBracketExpr).add(arrobj, ident"i"))
      else:
        arrPrimDistinct(distTy,
          nnkBracketExpr.newTree(arrobj, ident"i"),
          newAssignment(
            nnkBracketExpr.newTree(thevar, ident"i"),
            newCall($fld[1][2], newCall("move", ident"tmp")))
        )
        arrfor.add arrbody
    bodyif.add arrfor
  result = newIfStmt((testif, bodyif))

proc objAssign(thevar, jn, fld, fielddef: NimNode, distTy = newEmptyNode()):
    NimNode {.compiletime.} =
  let
    isDistinct = distTy.kind != nnkEmpty
    testif = newCall("isSome", jn)
    jnobj = gensym(nskVar, "jnobj")
    resvar = genSym(nskVar, "objres")
    identresvar = if isDistinct: newIdentDefs(resvar, distTy[0])
                  else: newIdentDefs(resvar, fld[1])
  var bodyif = newStmtList()
  bodyif.add(newNimNode(nnkVarSection).add(
    identresvar,
    newIdentDefs(jnobj, newEmptyNode(), newCall("get", jn)))
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
      let jnfieldstr = field[0].strval.newStrLitNode
      let jnfield = newNimNode(nnkBracketExpr).add(thevar, jnfieldstr)
      let arr = arrAssign(resfield, jnfield, field, fimpl)
      bodyif.add arr
    elif fimpl.isPrimitive:
      bodyif.add primAssign(resvar, jnobj, field)
    elif fimpl.kind in {nnkObjectTy, nnkRefTy}:
      let jnfieldstr = field[1].strval.newStrLitNode
      let jnfield = newNimNode(nnkBracketExpr).add(jnobj, jnfieldstr)
      bodyif.add objAssign(resfield, jnfield, field, fimpl)
  if isDistinct:
    bodyif.add newAssignment(thevar, newcall("unown",
      newCall($fld[1], resvar)
    ))
  else:
    bodyif.add newAssignment(thevar, newCall("unown", resvar))
  result = newIfStmt((testif, bodyif))

proc timeAssgn(thevar, jn, fld: NimNode, distTy = newEmptyNode()):
  NimNode {.compiletime.} =
  let
    isDistinct = distTy.kind != nnkEmpty
    testif = newCall("isSome", jn)
    resvar = genSym(nskVar, "timeres")
  var bodyif = newStmtList()
  if not isDistinct:
    bodyif.add(newNimNode(nnkVarSection).add(
      newIdentDefs(resvar, fld[1], newCall("get", jn))),
      newAssignment(thevar, newCall("unown", resvar))
    )
  else:
    bodyif.add(newNimNode(nnkVarSection).add(
      newIdentDefs(resvar, distTy[0], newCall("get", jn))),
      newAssignment(thevar, newCall("unown", newCall($fld[1], resvar)))
    )

  result = newIfStmt((testif, bodyif))

proc isTime(node: NimNode): bool {.compiletime.} =
  node.kind == nnkSym and $node == "Time"

macro to*(b: untyped, t: typed): untyped =
  result = newStmtList()
  let st = getType t
  let resvar = genSym(nskVar, "res")
  result.add newNimNode(nnkVarSection).add(
    newIdentDefs(resvar, st[1])
  )
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
  let objtyp = {nnkObjectTy, nnkRefTy}
  for field in reclist:
    if field.kind == nnkEmpty: continue
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
    elif fimpl.isPrimitive:
      result.add primAssign(resvar, b, field)
    elif fimpl.kind in objtyp:
      if field[1].isTime:
        result.add timeAssgn(resfield, nodefield, field)
        continue
      let resobj = objAssign(resfield, nodefield, field, fimpl)
      result.add resobj
    elif fimpl.kind == nnkDistinctTy:
      let distinctimpl = fimpl[0].getImpl
      if distinctimpl.isPrimitive:
        result.add primDistinct(resfield, b, field, distinctimpl)
      elif distinctimpl.kind in objtyp:
        if fimpl[0].isTime:
          result.add timeAssgn(resfield, nodefield, field, fimpl)
        else:
          result.add objAssign(resfield, nodefield, field, distinctimpl, fimpl)
    else:
      # temporary placeholder
      checknode field[1]
  result.add(newCall("unown", resvar))
  checknode result
