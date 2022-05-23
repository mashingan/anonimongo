# macro example for creating a function which both operates on Socket
# and AsyncSocket. multisock pragma and async pragma cannot be mixed together

import macros, sugar
from asyncnet import AsyncSocket
from net import Socket
from std/strutils import toLowerAscii

export Socket

{.hint[XDeclaredButNotUsed]: off.}

template inspect(n: untyped) =
  echo "========="
  dump `n`.kind
  dump `n`.len
  dump `n`.repr
  echo "========="

template nodeIs(n: NimNode, str: string): bool =
  n.kind == nnkIdent and ($n).toLowerAscii == str.toLowerAscii
template nodeIsAsyncSocket(n: NimNode): bool =
  n.nodeIs "AsyncSocket"
template nodeIsEmpty(n: NimNode): bool = n.kind == nnkEmpty


proc recReplaceForBracket(n: var NimNode, newident = "TheSocket") =
  if n.kind == nnkBracketExpr:
    var start = 1
    if n[0].nodeIs("Future"):
      n = n[1]
      start = 0
    for i in start ..< n.len:
      if n[i].kind == nnkEmpty: continue
      if n[i].nodeIsAsyncSocket:
        n[i] = ident newident
      else:
        var nn = n[i]
        nn.recReplaceForBracket newident
        n[i] = nn

template removeAndAssign(n: untyped) =
  var nn = `n`
  removeAwaitAsyncCheck nn
  `n` = nn

proc removeAwaitAsyncCheck(n: var NimNode) =
  if n.len < 1: return
  case n.kind
  of nnkEmpty: discard
  of nnkVarSection, nnkLetSection:
    for i, section in n:
      removeAndAssign n[i]
  of nnkCommand:
    if n[0].kind notin [nnkCall, nnkDotExpr, nnkEmpty] and $n[0] in ["await", "asyncCheck"]:
      n = newStmtList(n[1..^1])
      n.removeAwaitAsyncCheck
    else:
      for i in 0..<n.len:
        removeAndAssign n[i]
  of nnkAsgn:
    removeAndAssign n[1]
  of nnkOfBranch, nnkElse:
    removeAndAssign n[^1]
  of nnkBracketExpr:
    n.recReplaceForBracket "Socket"
  of nnkCall:
    if n[0].nodeIs("all") and n.len == 2: # removing the call of all in: `await all(op)`
      n = n[1]
      n.removeAwaitAsyncCheck
    else:
      for i in 0..<n.len:
        removeAndAssign n[i]
  else:
    for i in 0..<n.len:
      removeAndAssign n[i]

template replaceWaitforNode(n: untyped) =
  var nn = `n`
  nn.replaceWaitfor
  `n` = nn

proc replaceWaitfor(n: var NimNode) =
  case n.kind
  of nnkEmpty: return
  of nnkCall, nnkCommand:
    if n[0].nodeIs "waitfor":
      n[0] = ident "await"
      for i in 1 ..< n.len:
        replaceWaitforNode n[i]
  else:
    for i in 0 ..< n.len:
      replaceWaitforNode n[i]


type MultiSock* = AsyncSocket | Socket

proc multiproc(prc: NimNode): NimNode =
  let prcsync = prc.copy
  let syncparam = prcsync[3]
  if syncparam.kind != nnkEmpty:
    if syncparam[0].kind == nnkBracketExpr:
        if syncparam[0][0].kind == nnkIdent and $syncparam[0][0] == "Future":
          syncparam[0] = syncparam[0][1]
        var traverse = syncparam[0]
        traverse.recReplaceForBracket "Socket"
        syncparam[0] = traverse
    for i in 1..<syncparam.len:
      let socksync = syncparam[i]
      if socksync[1].nodeIsAsyncSocket:
        socksync[1] = ident "Socket"
      else:
        var ss1 = socksync[1]
        ss1.recReplaceForBracket "Socket"
        socksync[1] = ss1
  var prcbody = prcsync[^1]
  prcbody.removeAwaitAsyncCheck
  if prc[^3].kind != nnkEmpty:
    prc[^3].add(ident "async")
  else:
    prc[^3] = quote do: {.async.}
  replaceWaitforNode prc[^1]
  # inspect prcsync
  # inspect prc
  result = quote do:
    `prcsync`
    `prc`

proc multitype(ty: NimNode): NimNode =
  let genParamIsEmpty = ty[1].kind == nnkEmpty
  if not genParamIsEmpty and ty[1].kind == nnkGenericParams:
    ty[1].add quote do:
      TheSocket: AsyncSocket|Socket
  else:
    ty[1] = nnkGenericParams.newTree(newIdentDefs(ident "TheSocket", 
      nnkInfix.newTree(ident "|", ident "AsyncSocket", ident "Socket")))
    discard
  result = ty
  if ty[^1].kind != nnkObjectTy and ty[^1].kind == nnkEmpty:
    return

  var obj = ty[2]
  if ty[2].kind == nnkRefTy:
    obj = obj[0]
  if obj.nodeIsEmpty:
    inspect obj
    return
  if obj[^1].nodeIsEmpty:
    inspect obj[^1]
    return
  for i in 0 ..< obj[^1].len:
    # let identdef = ty[2][2][i]
    let identdef = obj[2][i]
    # if identdef[1].kind == nnkBracketExpr:
    #   for n in identdef[1]: inspect n
    if identdef.kind != nnkIdentDefs: continue
    if identdef[1].kind == nnkEmpty: continue
    if identdef[1].nodeIsAsyncSocket:
      identdef[1] = ident "TheSocket"
    else:
      var idf = identdef[1]
      idf.recReplaceForBracket
      identdef[1] = idf


macro multisock*(def: untyped): untyped =
  ## multisock macro operates on async proc definition
  ## with first param is AsyncSocket and returns Future
  ## which then creating the sync version of the function
  ## overload by removing `await` and `asyncCheck`
  case def.kind
  of nnkProcDef:
    result = def.multiproc
  of nnkIteratorDef:
    result = def
  else:
    let defg = def.multitype
    result = defg