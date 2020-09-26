import streams, tables, oids,  times
import macros, endians
from unicode import Rune, runes, `$`
from strutils import parseHexInt, join, parseInt, toHex,
  toLowerAscii, `%`
from strformat import fmt
from sequtils import toSeq
from lenientops import `/`, `+`, `*`

export strutils

import bsonify
export bsonify

when defined(oldto):
  import macroto
  export macroto
else:
  import macroto_v2
  export macroto_v2

# Bson
# Copyright Rahmatullah
# Bson implementation in Nim
# License MIT

## Bson
## ****
##
## Bson implementation in Nim based on `Bson spec`_. Users mainly will
## only need to use `BsonDocument`_ often as the main type instead
## of `BsonBase`_. But for specific uses, users sometimes to use
## ``sequtils.map`` to change the array/seq of some type to `BsonArray`_
## specifically and to `BsonBase`_ generically e.g.
##
## .. code-block:: Nim
##
##   import sequtils
##   var arrint = [1, 2, 3, 4, 5]
##   var bdoc = bson({
##     intfield: 1,
##     floatfield: 42.0,
##     strfield: "hello 異世界",
##     arrfield: arrint.map toBson,
##   })
##
## In case of immediate BsonDocument definition, we can define it e.g.
##
## .. code-block:: Nim
##
##   var bdoc = bson({
##     arrfield: ["hello", 1, 4.2, true]
##   })
##   doAssert $bdoc == """{"arfield":["hello",1,4.2,true]}"""
##
## Currently, based on test, we cannot add empty embed bson object literally
## and had to define a variable for it, and also a field started with number,
## e.g.
##
## .. code-block:: Nim
##
##   var _ = bson({ embed: {}, 1: "the field isn't supported too" })
##
## The snip above will throw compiler error because of empty set and macro
## error because of something ``nnkIntLitNode``.
##
## .. _Bson spec: http://bsonspec.org
## .. _BsonDocument: #BsonDocument
## .. _BsonBase: #BsonBase
## .. _BsonArray: #BsonArray

template writeLE*[T](s: Stream, val: T): untyped =
  ## Utility template to write any value to comply to
  ## less endian byte stream.
  when cpuEndian == bigEndian:
    var old = val
    var temp: T
    when sizeof(T) == 2:
      littleEndian16(addr temp, addr old)
    elif sizeof(T) == 4:
      littleEndian32(addr temp, addr old)
    elif sizeof(T) == 8:
      littleEndian64(addr temp, addr old)
    s.write temp
  else:
    s.write val

template readIntLE*(s: Stream, which: typedesc): untyped =
  ## Utility template to read int value which int type is
  ## specified in less endian format and adapt accordingly
  ## to current machine endianess.
  when cpuEndian == bigEndian:
    var tempLE: which
    when which is int32:
      var tempBE = s.readInt32
      swapEndian32(addr tempLE, addr tempBE)
    elif which is int64:
      var tempBE = s.readInt64
      swapEndian64(addr tempLE, addr tempBE)
    tempLE
  else:
    when which is int32:
      s.readInt32
    elif which is int64:
      s.readInt64


template readFloatLE(s: Stream): untyped =
  ## Read less endian float64
  when cpuEndian == bigEndian:
    var tempBE = s.readFloat64
    var tempLE: float64
    swapEndian64(addr tempLE, addr tempBE)
    tempLE
  else:
    s.readFloat64

template peekInt32LE*(s: Stream): untyped =
  ## Peek less endian int32
  when cpuEndian == bigEndian:
    var tempbe = s.peekInt32
    var temple: int32
    swapEndian32(addr temple, addr tempbe)
    temple
  else:
    s.peekInt32

proc bytes*(s: string): seq[byte] =
  ## Converts string to sequence of bytes.
  result = newseq[byte](s.len)
  for i, c in s:
    result[i] = c.byte

proc bytes*(o: Oid): seq[byte] =
  ## Converts ObjectId to sequence of bytes.
  result = newSeq[byte]()
  var
    count = 0
    oidstr = $o
  while count < oidstr.len:
    let chrtmp = oidstr[count .. count+1]
    result.add chrtmp.parseHexInt.byte
    count += 2

proc stringbytes*(s: seq[byte]): string =
  ## Convert byte stream seq to string.
  ## Usually used for reading binary stream.
  result = newstring(s.len)
  for i, b in s: result[i] = chr b

template `as`*(a, b: untyped): untyped =
  ## Sugar syntax for cast.
  cast[b](a)

type
  BsonBase* = ref object of RootObj
    ## BsonBase is type mimick object variant.
    ## Used as base of others Bson.
    kind*: BsonKind

  BsonInt32* = ref object of BsonBase
    value*: int32

  BsonInt64* = ref object of BsonBase
    value*: int64

  TimestampInternal = tuple
    increment: uint32
    timestamp: uint32

  BsonTimestamp* = ref object of BsonBase
    ## BsonTimestamp is actually int64 which represented
    ## by low dword as increment and high dword as timestamp.
    value*: TimestampInternal

  BsonDouble* = ref object of BsonBase
    value*: float64

  BsonNull* = ref object of BsonBase

  BsonBool* = ref object of BsonBase
    value*: bool

  BsonTime* = ref object of BsonBase
    value*: Time

  BsonArray* = ref object of BsonBase
    value*: seq[BsonBase]

  BsonString* = ref object of BsonBase
    ## BsonString supports unicode string and the implementation
    ## save it as Runes.
    value*: seq[Rune]

  BsonJs* = ref object of BsonBase
    ## JS code which represented as string, it's implemented as
    ## same as string.
    value*: seq[Rune]

  BsonEmbed* = ref object of BsonBase
    ## Embedded object as BsonDocument as its value. Defined
    ## in accordance with other BsonType for easier encoding/decoding
    ## to Bson stream.
    value*: BsonDocument

  BsonObjectId* = ref object of BsonBase
    value*: Oid

  BsonBinary* = ref object of BsonBase
    ## BsonBinary handles any kind of byte stream for
    ## Bson encoding/decoding.
    subtype*: BsonSubtype
    value*: seq[byte]

  BsonInternal = OrderedTableRef[string, BsonBase]
  BsonDocument* = ref object
    ## BsonDocument is the top of Bson type which
    ## has different structure tree with BsonBase family.
    ## Any user will mainly handle this often instead of
    ## BsonBase.
    table: BsonInternal
    stream: Stream
    encoded*: bool
      ## Flag whether the document already encoded
      ## to avoid repeated encoding.

  BsonKind* = enum
    ## Available Bson kind in accordance to Bson spec
    bkEmptyArray = (0x00.byte, "BsonEmptyArray")
    bkDouble = (0x01.byte, "BsonDouble")
    bkString = (0x02.byte, "BsonString")
    bkEmbed = "BsonEmbed"
    bkArray = "BsonArray"
    bkBinary = "BsonBinary"
    bkUndefined # bson spec: deprecated
    bkObjectId = "BsonObjectId"
    bkBool = "BsonBool"
    bkTime = "BsonTime"
    bkNull = "BsonNull"
    bkRegex
    bkDbPointer # bson spec: deprecated
    bkJs = "BsonJSFunction"
    bkSymbol    # bson spec: deprecated
    bkJsScope
    bkInt32 = "BsonInt32"
    bkTimestamp = "BsonTimestamp"
    bkInt64 = "BsonInt64"
    bkDecimal = "BsonDecimal"
    bkMaxKey = (0x7f.byte, "BsonMaxKey")
    bkMinKey = (0xff.byte, "BsonMinKey")
  
  BsonSubtype* = enum
    ## BsonSubtype is used to identify which kind of binary
    ## we encode/decode for that BsonBase. `stGeneric` is used
    ## generically when no specific subtype should be used.
    stGeneric = 0x00.byte
    stFunction stBinaryOld stUuidOld stUuid stMd5

  BsonFetchError* = object of Defect
    ## Bson error type converting wrong type from BsonBase

iterator pairs*(b: BsonDocument): (string, BsonBase) =
  for k, v in b.table:
    yield (k, v)

iterator mpairs*(b: BsonDocument): (unown string, var BsonBase) =
  for k, v in b.table.mpairs:
    yield (k, v)

proc `$`*(v: BsonBase): string

proc ms*(a: Time): int64 =
  ## Unix epoch in milliseconds.
  int64(a.toUnix*1000 + a.nanosecond/1e6)

proc `==`*(b: BsonBase, t: Time): bool =
  ## eq operator to fix some caveat caused by different precision
  ## between Nim's ``Time`` and Bson's ``Time``. Bson precision
  ## is milliseconds while Nim precision is nanoseconds.
  if b.kind != bkTime:
    raise newException(BsonFetchError,
      fmt"Invalid eq comparsion, expect {b} BsonTime, get {b.kind}")
  (b as BsonTime).value.ms == t.ms

proc `==`*(t: Time, b: BsonBase): bool =
  ## To support another eq operator position.
  if b.kind != bkTime:
    raise newException(BsonFetchError,
      fmt"Invalid eq comparsion, expect {b} BsonTime, get {b.kind}")
  t.ms == (b as BsonTime).value.ms

#[ will be completed later
template eqType(a, b: BsonBase, t: typedesc): bool =
  (a as t).value == (b as t).value

proc `==`*(a, b: BsonBase): bool =
  result = a.kind == b.kind and not (a.isNil or b.isNil)
  case a.kind
  of bkNull:
    result = true
  of bkString:
    result = $(a as BsonString).value == $(b as BsonString).value
  of bkInt32:
    result = eqType(a, b, BsonInt32)
  of bkInt64:
    result = eqType(a, b, BsonInt64)
  of bkDouble:
    result = eqType(a, b, BsonDouble)
  of bkTime:
    result = eqType(a, b, BsonTime)
  else:
    discard
]#

proc contains*(b: BsonDocument, key: string): bool =
  ## Check whether string ``key`` in BsonDocument ``b``
  runnableExamples:
    let bso = bson({
      field1: 1,
      field2: "field2",
      dynamic: true
    })
    doAssert "field1" in bso
    doAssert "field2" in bso
    doAssert "dynamic" in bso
  key in b.table

proc contains*(b: BsonBase, key: string): bool =
  ## Check whether string ``key`` in BsonBase ``b``.
  ## If the ``b`` is not BsonEmbed, throw ``BsonFetchError``.
  runnableExamples:
    let bso = bson({
      embed: {
        field1: 1,
        field2: "field2",
        dynamic: true
      }
    })
    let embedbso = bso["embed"]
    doAssert "field1" in embedbso
    doAssert "field2" in embedbso
    doAssert "dynamic" in embedbso
    #[ cannot add try-except clause in runnableExamples
    let bsarr = bsonArray(1, 2, 3.14, true)
    try:
      discard bsarr["wrong-type"]
      doAssert false
    except BsonFetchError:
      doAssert true
      ]#
  b.kind == bkEmbed and key in (b as BsonEmbed).value

proc `[]`*(b: BsonDocument, key: sink string): BsonBase =
  ## BsonDocument accessor for string key.
  runnableExamples:
    let bso = bson({
      field1: 1,
      field2: "field2",
      dynamic: true
    })
    doAssert bso["field1"] == 1
    #doAssert bso["not-exists"].isNone
  result = b.table[key]

proc `[]`*(b: BsonBase, key: sink string): BsonBase =
  ## BsonEmbed accessor for string key. Error when b is not BsonEmbed.
  runnableExamples:
    let bso = bson({
      embed: {
        field1: 1,
        field2: "field2",
        dynamic: true
      }
    })
    doAssert bso["embed"]["field1"] == 1
    doAssert bso["embed"]["field2"] == "field2"
    doAssert bso["embed"]["dynamic"].ofBool
  if b.kind != bkEmbed:
    raise newException(BsonFetchError,
      fmt"Invalid key retrieval of {b}, get {b.kind}")
  result = ((b as BsonEmbed).value)[key]

proc `[]`*(b: BsonBase, idx: sink int): BsonBase =
  ## BsonArray accessor for int index. Error when b is not BsonArray.
  runnableExamples:
    let bso = bson({
      embed: {
        field1: 1,
        field2: "field2",
        dynamic: true,
        bsarr: [1, 2, 3.14, true]
      }
    })
    let embedbso = bso["embed"]
    doAssert bso["embed"]["bsarr"][0] == 1
    doAssert bso["embed"]["bsarr"][1] == 2
    doAssert bso["embed"]["bsarr"][2] == 3.14
    doAssert bso["embed"]["bsarr"][3].ofBool
  if b.kind != bkArray:
    raise newException(BsonFetchError,
      fmt"Invalid indexed retrieval of {b}, get {b.kind}")
  let value = (b as BsonArray).value
  if idx >= value.len:
    raise newException(IndexError, fmt"{b}: {idx} not in 0..{value.len-1}")
  result = value[idx]

proc `[]`*[T: int | string](b: BsonBase, key: sink T): BsonBase =
  ## BsonBase Accessor whether indexed key or string key. Offload the
  ## actual operations to actual BsonBase accessors.
  runnableExamples:
    let bso = bson({
      embed: {
        field1: 1,
        field2: "field2",
        dynamic: true,
        bsarr: [1, 2, 3.14, true]
      }
    })
    doAssert bso["embed"]["field1"] == 1
    doAssert bso["embed"]["field2"] == "field2"
    doAssert bso["embed"]["dynamic"].ofBool
    doAssert bso["embed"]["bsarr"][0] == 1
    doAssert bso["embed"]["bsarr"][1] == 2
    doAssert bso["embed"]["bsarr"][2] == 3.14
    doAssert bso["embed"]["bsarr"][3].ofBool
  result = b[key]

proc `[]=`*(b: var BsonDocument, key: sink string, val: BsonBase) =
  ## BsonDocument setter with string key and the value. Because
  ## defined converter, any primitives and natives defined BsonKind
  ## automatically converted to BsonBase.
  runnableExamples:
    import times
    var bsonobj = bson()
    let currtime = now().toTime
    bsonobj["fieldstr"] = "this is string"
    bsonobj["fieldint"] = 1
    bsonobj["currtime"] = currtime
    bsonobj["thefloat"] = 42.0
    doAssert bsonobj["fieldstr"] == "this is string"
    doAssert bsonobj["fieldint"] == 1
    doAssert bsonobj["currtime"] == currtime
    doAssert bsonobj["thefloat"] == 42.0
  
  b.encoded = false
  b.table[key] = val

proc mget*(b: var BsonDocument, key: sink string): var BsonBase =
  ## Return a mutable field access, any change to this variable
  ## affect BsonDocument and immediately turned ``encoded`` field
  ## off/false.
  runnableExamples:
    import times
    var bsonobj = bson()
    let currtime = now().toTime
    bsonobj["fieldstr"] = "this is string"
    bsonobj["fieldint"] = 1
    bsonobj["currtime"] = currtime
    bsonobj["thefloat"] = 42.0
    let (_, _) = encode bsonobj
    doAssert bsonobj.encoded
    bsonobj.mget("fieldint") = 2
    doAssert not bsonobj.encoded
  
  b.encoded = false
  b.table[key]

proc mget*(b: var BsonBase, key: sink string): var BsonBase =
  ## Actual a mutable accessor for string key BsonEmbed.
  ## Throw error when it's not BsonEmbed.
  runnableExamples:
    var bbase = bson({
      embed: { f1: 1, f2: "nice", f3: true }
    })
    bbase.mget("embed").mget("f2") = false
    doAssert not bbase["embed"]["f2"].ofBool
  if b.kind != bkEmbed:
    raise newException(BsonFetchError,
      fmt"Invalid key retrieval of {b}, get {b.kind}")
  result = (b as BsonEmbed).value.table[key]

proc mget*(b: var BsonBase, index: sink int): var BsonBase =
  ## Actual a mutable accessor for indexed key BsonArray.
  ## Throw error when it's not BsonArray.
  runnableExamples:
    var bbase = bsonArray(1, 2, 3, 4.5)
    bbase.mget(2) = 5
    doAssert bbase[2] == 5
  if b.kind != bkArray:
    raise newException(BsonFetchError,
      fmt"Invalid index retrieval {b}, get {b.kind}")
  result = (b as BsonArray).value[index]
  
proc `[]=`*(b: var BsonBase, key: sink string, val: BsonBase) =
  ## Shortcut for assigning BsonEmbed key retrieved from `mget` BsonBase
  if b.kind != bkEmbed:
    raise newException(BsonFetchError,
      fmt"Invalid Bson kind key retrieval of {b}, get {b.kind}")
  (b as BsonEmbed).value.table[key] = val

proc add*(b: var BsonArray, v: BsonBase) =
  ## Add element to BsonArray
  runnableExamples:
    var barray = bsonArray()
    barray.add 5
    barray.add "hello, 異世界"
    barray.add true
    doAssert barray.len == 3
    doAssert barray[2].ofBool
  b.value.add v

proc add*(b: var BsonBase, v: BsonBase) =
  ## Shortcut for adding element to BsonBase that's actually BsonArray.
  ## Use it with combination of `mget` for retriving the var BsonBase
  if b.kind != bkArray:
    raise newException(BsonFetchError,
      fmt"Invalid Bson kind add value of {b}, get {b.kind}")
  var barray = b as BsonArray
  barray.value.add v

proc del*(b: var BsonDocument, key: string) =
  ## Delete a field given from string key. Do nothing when there's no
  ## targeted field
  runnableExamples:
    var b = bson({ f1: 1, f2: 2, f3: 3 })
    doAssert b.len == 3
    b.del "f1"
    doAssert b.len == 2
    b.del "f2"
    doAssert b.len == 1
    b.del "f2"
    doAssert b.len == 1
  b.table.del key

proc len*(b: BsonDocument): int =
  ## Return the how many key-value in BsonDocument.
  runnableExamples:
    var b = bson()
    doAssert b.len == 0
    b["field1"] = 1
    doAssert b.len == 1
    b.del "field1"
    doAssert b.len == 0
  b.table.len

proc len*(b: BsonArray): int =
  ## Return the length of BsonArray
  runnableExamples:
    var b = bsonArray()
    b.add 5
    b.add "hello, 異世界"
    b.add true
    doAssert b.len == 3
  b.value.len

proc len*(b: BsonBase): int =
  ## Shortcut for returning the array of BsonEmbed or BsonArray.
  ## Throw BsonFetchError in case of not both BsonKind
  case b.kind
  of bkArray:
    result = (b as BsonArray).value.len
  of bkEmbed:
    result = (b as BsonEmbed).value.len
  else:
    raise newException(BsonFetchError,
      fmt"Invalid bson length retrieval of {b}," &
      fmt"expected bkArray/bkEmbed or BsonDocument got {b.kind}")

iterator keys*(b: BsonDocument): string =
  for k in b.table.keys:
    yield k

proc quote(key: string): string =
  result = '"' & key & '"'

proc `$`*(doc: BsonDocument): string

proc `$`(doc: BsonBinary): string =
  ## Stringified BsonBinary.
  result = fmt"binary({quote($doc.subtype)}, {quote(doc.value.stringbytes)})"

proc `$`*(v: BsonBase): string =
  ## Stringified BsonBase.
  runnableExamples:
    import times
    let currtime = now().toTime
    doAssert $"hello 異世界".toBson == "\"hello 異世界\""
    doAssert $1.toBson == $1
    doAssert $(4.2.toBson) == $4.2
    doAssert $(currtime.toBson) == '"' & $currtime & '"'
    doAssert $(bsonNull()) == "null"
    doAssert $bsonArray(1, 3.14, true) == "[1,3.14,true]"
  case v.kind
  of bkString:
    result = quote $(v as BsonString).value
  of bkInt32:
    result = $(v as BsonInt32).value
  of bkInt64:
    result = $(v as BsonInt64).value
  of bkDouble:
    result = $(v as BsonDouble).value
  of bkBool:
    result = $(v as BsonBool).value
  of bkNull:
    result = "null"
  of bkTime:
    result = quote $(v as BsonTime).value
  of bkArray:
    result = '[' & (v as BsonArray).value.join(",") & ']'
  of bkEmbed:
    result = $(v as BsonEmbed).value
  of bkObjectId:
    result = fmt"ObjectId({quote $(v as BsonObjectId).value})"
  of bkBinary:
    result = $(v as BsonBinary)
  of bkTimestamp:
    let doc = v as BsonTimestamp
    result = fmt"timestamp(increment:{doc.value[0]}, timestamp:{doc.value[1]})"
  of bkJs:
    result = quote $(v as BsonJs).value
  else:
    result = ""

proc `$`*(doc: BsonDocument): string =
  ## Stringified BsonDocument.
  runnableExamples:
    let bsonempty = bson({})
    let simple = bson({ field1: 1, "field2": "two", "field3": 3.14,
      arr: [], embed: bsonempty})
    doAssert $simple == """{"field1":1,"field2":"two","field3":3.14,"arr":[],"embed":{}}"""
  result = "{"
  for k, v in doc:
    result &= k.quote & ":" & $v & ','
  if result.len > 1:
    result[^1] = '}'
  else:
    result &= '}'


proc writeKey(s: Stream, key: string, kind: BsonKind): int32 =
  s.write kind.byte
  s.write key
  s.write 0x00.byte
  result = int32(1 + key.len + 1)

proc encode*(doc: BsonDocument): (int, string)

proc encode(s: Stream, key: string, doc: BsonInt32): int =
  result = s.writeKey(key, bkInt32) + doc.value.sizeof
  s.writeLE doc.value

proc encode(s: Stream, key: string, doc: BsonInt64): int =
  result = s.writeKey(key, bkInt64) + doc.value.sizeof
  s.writeLE doc.value

proc encode(s: Stream, key: string, doc: BsonString | BsonJs): int =
  let sbytes = ($doc.value).bytes
  result = s.writeKey(key, doc.kind) + int32.sizeof + sbytes.len + 1
  s.writeLE (sbytes.len + 1).int32
  for c in sbytes: s.write c
  s.write 0x00.byte

proc encode(s: Stream, key: string, doc: BsonDouble): int =
  result = s.writeKey(key, bkDouble) + doc.value.sizeof
  s.writeLE doc.value

proc encode(s: Stream, key: string, doc: BsonArray): int =
  var embedArray = BsonDocument(
    table: newOrderedTable[string, BsonBase](),
    stream: newStringStream()
  )
  for i, b in doc.value:
    embedArray[$i] = b

  let (hlength, currbuff) = encode embedArray
  result = s.writeKey(key, bkArray) + hlength
  s.write currbuff

proc encode(s: Stream, key: string, doc: BsonBool): int =
  result = s.writeKey(key, bkBool) + byte.sizeof
  if doc.value: s.write 0x01.byte
  else: s.write 0x00.byte

proc encode(s: Stream, key: string, doc: BsonTime): int =
  result = s.writeKey(key, bkTime) + int64.sizeof
  let timeval = doc.value.ms
  s.writeLE timeval

proc encode(s: Stream, key: string, doc: BsonDocument): int =
  result = s.writeKey(key, bkEmbed)
  let (embedlen, embedstr) = encode doc
  result += embedlen
  s.write embedstr

proc encode(s: Stream, key: string, doc: BsonNull): int =
  result = s.writeKey(key, bkNull)

proc encode(s: Stream, key: string, doc: BsonObjectId): int =
  result = s.writeKey(key, bkObjectId) + doc.value.bytes.len
  for b in doc.value.bytes:
    s.write b

proc encode(s: Stream, key: string, doc: BsonBinary): int =
  result = s.writeKey(key, bkBinary) + int32.sizeof + byte.sizeof + doc.value.len
  s.writeLE doc.value.len.int32
  s.write doc.subtype.byte
  for b in doc.value:
    s.writeLE b

proc encode(s: Stream, key: string, doc: BsonTimestamp): int =
  result = s.writeKey(key, bkTimestamp) + uint64.sizeof
  s.writeLE doc.value[0]
  s.writeLE doc.value[1]

proc encode*(doc: BsonDocument): (int, string) =
  ## Encode BsonDocument and return it into length of binary string
  ## and the binary string itself.
  if doc.encoded:
    doc.stream.setPosition 0
    let docstr = doc.stream.readAll
    return (docstr.len, docstr)
  var length = 4 + 1
  var buff = ""
  doc.stream.writeLE length.int32
  for k, v in doc:
    case v.kind
    of bkInt32:
      length += doc.stream.encode(k, v as BsonInt32)
    of bkInt64:
      length += doc.stream.encode(k, v as BsonInt64)
    of bkString:
      length += doc.stream.encode(k, v as BsonString)
    of bkDouble:
      length += doc.stream.encode(k, v as BsonDouble)
    of bkArray:
      length += doc.stream.encode(k, v as BsonArray)
    of bkEmbed:
      let bdoc = (v as BsonEmbed).value
      if bdoc.isNil: continue
      let ndoc = bdoc as BsonDocument
      length += doc.stream.encode(k, ndoc)
    of bkBool:
      length += doc.stream.encode(k, v as BsonBool)
    of bkTime:
      length += doc.stream.encode(k, v as BsonTime)
    of bkNull:
      length += doc.stream.encode(k, v as BsonNull)
    of bkObjectId:
      length += doc.stream.encode(k, v as BsonObjectId)
    of bkBinary:
      length += doc.stream.encode(k, v as BsonBinary)
    of bkTimestamp:
      length += doc.stream.encode(k, v as BsonTimestamp)
    of bkJs:
      length += doc.stream.encode(k, v as BsonJs)
    else:
      discard

  doc.stream.write 0x00.byte
  doc.stream.setPosition 0
  doc.stream.writeLE length.int32
  doc.stream.setPosition 0
  buff = doc.stream.readAll
  doc.encoded = true
  result = (length, buff)

converter toBson*(v: BsonBase): BsonBase = v
  ## Id conversion BsonBase to itself. For `bson macro<#bson.m,untyped>`_.

converter toBson*(value: int|int32): BsonBase =
  ## Convert int or int32 to BsonBase automatically.
  BsonInt32(value: value.int32, kind: bkInt32) as BsonBase

converter toBson*(value: int64): BsonBase =
  ## Convert int64 to BsonBase automatically.
  BsonInt64(value: value, kind: bkInt64)# as BsonBase

converter toBson*(values: string | seq[Rune]): BsonBase =
  ## Convert whether string or Runes to BsonString/BsonBase.
  when values.type is string:
    let newval = toSeq(values.runes)
  else:
    let newval = values
  BsonString(kind: bkString, value: newval)# as BsonBase

converter toBson*(value: SomeFloat): BsonBase =
  BsonDouble(value: value.float64, kind: bkDouble)# as BsonBase

converter toBson*(value: seq[BsonBase]): BsonBase =
  ## Convert seq of BsonBase into BsonArray/BsonBase.
  BsonArray(value: value, kind: bkArray)# as BsonBase

converter toBson*(value: bool): BsonBase =
  BsonBool(value: value, kind: bkBool)

converter toBson*(value: Time): BsonBase =
  BsonTime(value: value, kind: bkTime)

converter toBson*(value: Oid): BsonBase =
  BsonObjectId(value: value, kind: bkObjectId)

converter toBson*(value: BsonDocument): BsonBase =
  ## Convert BsonDocument into BsonEmbed.
  BsonEmbed(value: value, kind: bkEmbed)

converter toBson*(value: openarray[byte]): BsonBase =
  ## Convert any bytes into as generic BsonBinary.
  BsonBinary(value: @value, kind: bkBinary, subtype: stGeneric)

converter toBson*(value: TimestampInternal): BsonBase =
  BsonTimestamp(value: value, kind: bkTimestamp)

proc bsonNull*: BsonBase =
  ## Convenient BsonNull init.
  BsonNull(kind: bkNull)

proc isNil*(b: BsonBase): bool =
  ## Check whether BsonBase is literally nil or it's BsonNull.
  b == nil or (b as BsonNull).kind == bkNull

proc isNil*(b: BsonDocument): bool =
  ## Check whether BsonDocument is literally nil or it's empty.
  b == nil or b.len == 0

proc bsonArray*(args: varargs[BsonBase, toBson]): BsonBase =
  ## Change a variable arguments into BsonArray.
  (@args).toBson

proc bsonBinary*(binstr: string, subtype = stGeneric): BsonBase =
  ## Change a string BsonBinary.
  BsonBinary(value: binstr.bytes, subtype: subtype, kind: bkBinary)

proc bsonBinary*(binseq: seq[byte], subtype = stGeneric): BsonBase =
  ## Overload with seq of byte to be BsonBinary
  BsonBinary(value: binseq, subtype: subtype, kind: bkBinary)

proc bsonJs*(code: string | seq[Rune]): BsonBase =
  ## BsonJs init for string or Runes.
  when code.type is string:
    let value = toSeq code.runes
  else:
    let value = code
  BsonJs(value: value, kind: bkJs)

proc newBson*(table = newOrderedTable[string, BsonBase](),
    stream: Stream = newStringStream()): BsonDocument =
  ## A primordial BsonDocument allocators. Preferably to use
  ## `bson macro<#bson.m,untyped>`_ instead, except the
  ## need to specify the stream used for the BsonDocument.
  BsonDocument(
    table: table,
    stream: stream
  )

proc decodeKey(s: Stream): (string, BsonKind) =
  let kind = s.readInt8.BsonKind
  var buff = ""
  while true:
    var achar = s.readChar
    if achar.byte == 0:
      break
    buff &= achar
  result = (buff, kind)

proc decode*(strbytes: string): BsonDocument

proc decodeArray(s: Stream): seq[BsonBase] =
  let length = s.peekInt32LE
  let doc = decode s.readStr(length)
  var ordTable = newOrderedTable[int, BsonBase]()
  for k, v in doc:
    var num = 0
    try:
      num = parseInt k
      ordTable[num] = v
    except ValueError:
      continue

  for _, d in ordTable:
    result.add d

proc decodeString(s: Stream): seq[Rune] =
  let length = s.readIntLE int32
  let buff = s.readStr(length-1)
  discard s.readChar # discard last 0x00
  result = toSeq(buff.runes)

proc decodeBool(s: Stream): bool =
  case s.readInt8
  of 0x00: false
  of 0x01: true
  else: false

proc decodeObjectId(s: Stream): Oid =
  var buff = ""
  for _ in 1 .. 12:
    buff &= s.readChar.ord.toHex(2).toLowerAscii
  result = parseOid buff.cstring

proc readMilliseconds(s: Stream): Time =
  let
    currsec = s.readIntLE int64
    secfrac = int64(currsec / 1000.0)
    millfrac = int64((currsec mod 1000) * 1e6)
  initTime(secfrac, millfrac)

proc decodeBinary(s: Stream): (BsonSubtype, seq[byte]) =
  var thebytes = newseq[byte]()
  let length = s.readIntLE int32
  let subtype = s.readChar.BsonSubtype
  for _ in 1 .. length:
    thebytes.add s.readChar.byte
  result = (subtype, thebytes)

proc decode(s: Stream): (string, BsonBase) =
  let (key, kind) = s.decodeKey
  var val: BsonBase
  case kind
  of bkInt32:
    val = BsonInt32(kind: kind, value: s.readIntLE int32)
  of bkInt64:
    val = BsonInt64(kind: kind, value: s.readIntLE int64)
  of bkDouble:
    val = BsonDouble(kind: kind, value: s.readFloatLE)
  of bkTime:
    # bson repr need time from milliseconds while
    # nim fromUnix is from seconds
    val = BsonTime(kind: kind, value: s.readMilliSeconds)
  of bkNull:
    val = bsonNull()
  of bkArray:
    val = BsonArray(kind: kind, value: s.decodeArray)
  of bkString:
    val = BsonString(kind: kind, value: s.decodeString)
  of bkBool:
    val = BsonBool(kind: kind, value: s.decodeBool)
  of bkObjectId:
    val = BsonObjectId(kind: kind, value: s.decodeObjectId)
  of bkEmbed:
    let doclen = s.peekInt32LE
    val = BsonEmbed(kind: kind, value: s.readStr(doclen).decode)
  of bkBinary:
    let (subtype, thebyte) = s.decodeBinary
    val = BsonBinary(kind: kind, subtype: subtype, value: thebyte)
  of bkTimestamp:
    val = BsonTimestamp(kind: kind, value: (s.readUint32, s.readUint32))
  of bkJs:
    val = BsonJs(kind: kind, value: s.decodeString)
  else:
    val = bsonNull()
  result = (key, val)

proc decode*(strbytes: string): BsonDocument =
  ## Decode a binary stream into BsonDocument.
  var
    stream = newStringStream(strbytes)
    table = newOrderedTable[string, BsonBase]()
  discard stream.readIntLE(int32)
  while not stream.atEnd:
    let (key, val) = stream.decode
    table[key] = val
    if not stream.atEnd and stream.peekInt8 == 0:
      break

  stream.setPosition 0
  BsonDocument(
    table: table,
    stream: stream,
    encoded: true
  )

proc newBson*(table: varargs[(string, BsonBase)]): BsonDocument =
  var tableres = newOrderedTable[string, BsonBase]()
  ## Overload newBson with table definition only and stream default to
  ## StringStream. In most case, use `bson macro<#bson.m,untyped>`_.
  for t in table:
    tableres[t[0]] = t[1]
  BsonDocument(
    table: tableres,
    stream: newStringStream()
  )

template bsonFetcher(b: BsonBase, targetKind: BsonKind,
    inheritedType: typedesc, targetType: untyped): untyped =
  if b.kind != targetKind:
    raise newException(BsonFetchError, "Cannot convert $# of $# to $#" %
      [$b, $b.kind, $targetType])
  else:
    result = (b as inheritedType).value as targetType

converter ofInt32*(b: BsonBase): int32 =
  bsonFetcher(b, bkInt32, BsonInt32, int32)

converter ofInt64*(b: BsonBase): int64 =
  bsonFetcher(b, bkInt64, BsonInt64, int64)

converter ofInt*(b: BsonBase): int =
  if b.kind == bkInt32:
    bsonFetcher(b, bkInt32, BsonInt32, int)
  else:
    bsonFetcher(b, bkInt64, BsonInt64, int)

converter ofDouble*(b: BsonBase): float64 =
  bsonFetcher(b, bkDouble, BsonDouble, float64)

converter ofString*(b: BsonBase): string =
  ## ofString converter able to extract whether BsonString or BsonJs
  ## because both of implementation is exactly same with only different
  ## their BsonKind.
  if b.kind == bkString:
    $(b as BsonString).value
  elif b.kind == bkJs:
    $(b as BsonJs).value
  elif b.kind == bkBinary:
    (b as BsonBinary).value.stringbytes
  else:
    raise newException(BsonFetchError,
      fmt"""Cannot convert {b} of {b.kind} to string or JsCode""")

converter ofTime*(b: BsonBase): Time =
  bsonFetcher(b, bkTime, BsonTime, Time)

converter ofObjectId*(b: BsonBase): Oid =
  bsonFetcher(b, bkObjectId, BsonObjectId, Oid)

converter ofArray*(b: BsonBase): seq[BsonBase] =
  bsonFetcher(b, bkArray, BsonArray, seq[BsonBase])

converter ofBool*(b: BsonBase): bool =
  bsonFetcher(b, bkBool, BsonBool, bool)

converter ofEmbedded*(b: BsonBase): BsonDocument =
  bsonFetcher(b, bkEmbed, BsonEmbed, BsonDocument)

converter ofBinary*(b: BsonBase): seq[byte] =
  bsonFetcher(b, bkBinary, BsonBinary, seq[byte])

converter ofTimestamp*(b: BsonBase): TimestampInternal =
  bsonFetcher(b, bkTimestamp, BsonTimestamp, TimestampInternal)

template bson*(): untyped = bson({})
  ## Convenience for empty bson.

template `!>`*(b: untyped): BsonDocument = bson(b)
  ## Convenient operator over `bson`