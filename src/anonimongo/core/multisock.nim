# macro example for creating a function which both operates on Socket
# and AsyncSocket. multisock pragma and async pragma cannot be mixed together

import macros, sugar

{.hint[XDeclaredButNotUsed]: off.}

template inspect(n: untyped) =
  echo "========="
  dump `n`.kind
  dump `n`.len
  dump `n`.repr
  echo "========="

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
    if n[0].kind != nnkDotExpr and $n[0] in ["await", "asyncCheck"]:
      n = newStmtList(n[1..^1])
  of nnkAsgn:
    removeAndAssign n[1]
  of nnkOfBranch, nnkElse:
    removeAndAssign n[^1]
  else:
    for i in 0..<n.len:
      removeAndAssign n[i]

macro multisock*(prc: untyped): untyped =
  ## multisock macro operates on async proc definition
  ## with first param is AsyncSocket and returns Future
  ## which then creating the sync version of the function
  ## overload by removing `await` and `asyncCheck`
  let prcsync = prc.copy
  let syncparam = prcsync[3]
  if syncparam.kind != nnkEmpty:
    syncparam[0] = syncparam[0][1]
    for i in 1..<syncparam.len:
      let socksync = syncparam[i]
      if $socksync[1] == "AsyncSocket":
        socksync[1] = ident "Socket"
  var prcbody = prcsync[^1]
  prcbody.removeAwaitAsyncCheck
  if prc[^3].kind != nnkEmpty:
    prc[^3].add(ident "async")
  else:
    prc[^3] = quote do: {.async.}
  inspect prcsync
  inspect prc
  result = quote do:
    `prcsync`
    `prc`