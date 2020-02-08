import streams, tables, oids,  times
import macros, endians, options
from unicode import Rune, runes, `$`
from strutils import parseHexInt, join, parseInt, toHex,
  toLowerAscii, `%`
from strformat import fmt
from sequtils import toSeq
from lenientops import `/`, `+`, `*`
from sugar import dump

export strutils
export options

include bsonify
include macroto

template writeLE*[T](s: Stream, val: T): untyped =
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
  when cpuEndian == bigEndian:
    var tempBE = s.readFloat64
    var tempLE: float64
    swapEndian64(addr tempLE, addr tempBE)
    tempLE
  else:
    s.readFloat64

template peekInt32LE*(s: Stream): untyped =
  when cpuEndian == bigEndian:
    var tempbe = s.peekInt32
    var temple: int32
    swapEndian32(addr temple, addr tempbe)
    temple
  else:
    s.peekInt32

proc bytes*(s: string): seq[byte] =
  result = newseq[byte](s.len)
  for i, c in s:
    result[i] = c.byte

proc bytes*(o: Oid): seq[byte] =
  result = newSeq[byte]()
  var
    count = 0
    oidstr = $o
  while count < oidstr.len:
    let chrtmp = oidstr[count .. count+1]
    result.add chrtmp.parseHexInt.byte
    count += 2

proc stringbytes*(s: seq[byte]): string =
  result = newstring(s.len)
  for i, b in s: result[i] = chr b

template `as`*(a, b: untyped): untyped =
  cast[b](a)

type
  BsonBase* = ref object of RootObj
    kind*: BsonKind

  BsonInt32* = ref object of BsonBase
    value*: int32

  BsonInt64* = ref object of BsonBase
    value*: int64

  TimestampInternal = tuple
    increment: uint32
    timestamp: uint32

  BsonTimestamp* = ref object of BsonBase
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
    value*: seq[Rune]

  BsonEmbed* = ref object of BsonBase
    value*: BsonDocument

  BsonObjectId* = ref object of BsonBase
    value*: Oid

  BsonBinary* = ref object of BsonBase
    subtype*: BsonSubtype
    value*: seq[byte]

  BsonInternal = OrderedTableRef[string, BsonBase]
  BsonDocument* = ref object
    table: BsonInternal
    stream: Stream
    encoded*: bool

  BsonKind* = enum
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
    bkJs
    bkSymbol    # bson spec: deprecated
    bkJsScope
    bkInt32 = "BsonInt32"
    bkTimestamp = "BsonTimestamp"
    bkInt64 = "BsonInt64"
    bkDecimal = "BsonDecimal"
    bkMaxKey = (0x7f.byte, "BsonMaxKey")
    bkMinKey = (0xff.byte, "BsonMinKey")
  
  BsonSubtype* = enum
    stGeneric = 0x00.byte
    stFunction stBinaryOld stUuidOld stUuid stMd5

  BsonFetchError* = ref object of Exception

iterator pairs*(b: BsonDocument): (string, BsonBase) =
  for k, v in b.table:
    yield (k, v)


# Added to bypass getting from Option or BsonBase
proc get*(b: BsonBase): BsonBase = b
proc isSome*(b: BsonBase): bool = true
proc isNone*(b: BsonBase): bool = false

proc contains*(b: BsonDocument, key: string): bool =
  key in b.table

proc contains*(b: BsonBase, key: string): bool =
  if b.kind != bkEmbed:
    raise BsonFetchError(msg: fmt"Invalid key retrieval, get {b.kind}")
  key in (b as BsonEmbed).value

proc `[]`*(b: BsonDocument, key: sink string): Option[BsonBase] =
  if key in b:
    result = some b.table[key]
  else:
    result = none BsonBase

proc `[]`*(b: BsonBase, key: sink string): BsonBase =
  if b.kind != bkEmbed:
    raise BsonFetchError(msg: fmt"Invalid key retrieval, get {b.kind}")
  result = ((b as BsonEmbed).value)[key].get

proc `[]`*(b: BsonBase, idx: sink int): BsonBase =
  if b.kind != bkArray:
    raise BsonFetchError(msg: fmt"Invalid indexed retrieval, get {b.kind}")
  let value = (b as BsonArray).value
  if idx >= value.len:
    raise newException(IndexError, fmt"{idx} not in 0..{value.len-1}")
  result = value[idx]

proc `[]`*[T: int | string](b: Option[BsonBase], key: sink T): BsonBase =
  result = b.get[key]

proc `[]=`*(b: var BsonDocument, key: sink string, val: BsonBase) =
  b.encoded = false
  b.table[key] = val

proc mget*(b: var BsonDocument, key: sink string): var BsonBase =
  b.table[key]

proc mget*(b: var BsonBase, key: sink string): var BsonBase =
  if b.kind != bkEmbed:
    raise BsonFetchError(msg: fmt"Invalid key retrieval, get {b.kind}")
  result = (b as BsonEmbed).value.table[key]

proc mget*(b: var BsonBase, index: sink int): var BsonBase =
  if b.kind != bkArray:
    raise BsonFetchError(msg: fmt"Invalid index retrieval, get {b.kind}")
  result = (b as BsonArray).value[index]


proc len*(b: BsonDocument): int =
  b.table.len

proc quote(key: string): string =
  result = '"' & key & '"'

proc `$`*(doc: BsonDocument): string

proc `$`(doc: BsonBinary): string =
  result = fmt"binary({quote($doc.subtype)}, {quote(doc.value.stringbytes)})"

proc `$`*(v: BsonBase): string =
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
  else:
    result = ""

proc `$`*(doc: BsonDocument): string =
  result = "{"
  for k, v in doc:
    result &= k.quote & ":" & $v & ','
  if result.len > 1:
    result[^1] = '}'
  else:
    result &= '}'


proc writeKey(s: Stream, key: string, kind: BsonKind) =
  s.write kind.byte
  s.write key
  s.write 0x00.byte

proc encode*(doc: BsonDocument): (int, string)

proc encode(s: Stream, key: string, doc: BsonInt32): int =
  result = 1 + key.len + 1 + 4
  s.writeKey key, bkInt32
  s.writeLE doc.value

proc encode(s: Stream, key: string, doc: BsonInt64): int =
  result = 1 + key.len + 1 + 8
  s.writeKey key, bkInt64
  s.writeLE doc.value

proc encode(s: Stream, key: string, doc: BsonString): int =
  let sbytes = ($doc.value).bytes
  result = 1 + key.len + 1 + 4 + sbytes.len + 1
  s.writeKey key, bkString
  s.writeLE (sbytes.len + 1).int32
  for c in sbytes: s.write c
  s.write 0x00.byte

proc encode(s: Stream, key: string, doc: BsonDouble): int =
  result = 1 + key.len + 1 + 8
  s.writeKey key, bkDouble
  s.writeLE doc.value

proc encode(s: Stream, key: string, doc: BsonArray): int =
  var embedArray = BsonDocument(
    table: newOrderedTable[string, BsonBase](),
    stream: newStringStream()
  )
  for i, b in doc.value:
    embedArray[$i] = b

  s.writeKey key, bkArray
  let (hlength, currbuff) = encode embedArray
  result = 1 + key.len + 1 + hlength
  s.write currbuff

proc encode(s: Stream, key: string, doc: BsonBool): int =
  result = 1 + key.len + 1 + 1
  s.writeKey key, bkBool
  if doc.value: s.write 0x01.byte
  else: s.write 0x00.byte

proc encode(s: Stream, key: string, doc: BsonTime): int =
  result = 1 + key.len + 1 + 8
  s.writeKey key, bkTime
  let timesec = doc.value.toUnix
  let timenano = doc.value.nanosecond
  let timeval = int64(timesec*1000 + timenano/1e6)
  s.writeLE timeval

proc encode(s: Stream, key: string, doc: BsonDocument): int =
  result = 1 + key.len + 1
  s.writeKey key, bkEmbed
  let (embedlen, embedstr) = encode doc
  result += embedlen
  s.write embedstr

proc encode(s: Stream, key: string, doc: BsonNull): int =
  result = 1 + key.len + 1
  s.writeKey key, bkNull

proc encode(s: Stream, key: string, doc: BsonObjectId): int =
  result = 1 + key.len + 1 + 12
  s.writeKey key, bkObjectId
  for b in doc.value.bytes:
    s.write b

proc encode(s: Stream, key: string, doc: BsonBinary): int =
  result = 1 + key.len + 1 + 4 + 1 + doc.value.len
  s.writeKey key, bkBinary
  s.writeLE doc.value.len.int32
  s.write doc.subtype.byte
  for b in doc.value:
    s.writeLE b

proc encode(s: Stream, key: string, doc: BsonTimestamp): int =
  result = 1 + key.len + 1 + 8
  s.writeKey key, bkTimestamp
  s.writeLE doc.value[0]
  s.writeLE doc.value[1]

proc encode*(doc: BsonDocument): (int, string) =
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
      let ndoc = (v as BsonEmbed).value as BsonDocument
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

converter toBson*(value: int|int32): BsonBase =
  BsonInt32(value: value.int32, kind: bkInt32) as BsonBase

converter toBson*(value: int64): BsonBase =
  BsonInt64(value: value, kind: bkInt64)# as BsonBase

converter toBson*(values: string | seq[Rune]): BsonBase =
  when values.type is string:
    let newval = toSeq(values.runes)
  else:
    let newval = values
  BsonString(kind: bkString, value: newval)# as BsonBase

converter toBson*(value: SomeFloat): BsonBase =
  BsonDouble(value: value.float64, kind: bkDouble)# as BsonBase

converter toBson*(value: seq[BsonBase]): BsonBase =
  BsonArray(value: value, kind: bkArray)# as BsonBase

converter toBson*(value: bool): BsonBase =
  BsonBool(value: value, kind: bkBool)

converter toBson*(value: Time): BsonBase =
  BsonTime(value: value, kind: bkTime)

converter toBson*(value: Oid): BsonBase =
  BsonObjectId(value: value, kind: bkObjectId)

converter toBson*(value: BsonDocument): BsonBase =
  BsonEmbed(value: value, kind: bkEmbed)

converter toBson*(value: openarray[byte]): BsonBase =
  BsonBinary(value: @value, kind: bkBinary, subtype: stGeneric)

converter toBson*(value: TimestampInternal): BsonBase =
  BsonTimestamp(value: value, kind: bkTimestamp)

proc bsonNull*: BsonBase =
  BsonNull(kind: bkNull)

proc isNil*(b: BsonBase): bool =
  b == nil or (b as BsonNull).kind == bkNull

proc isNil*(b: BsonDocument): bool =
  b == nil or b.len == 0

proc isNil*(b: Option[BsonBase]): bool =
  not b.isNone and b.get.isNil

proc bsonArray*(args: varargs[BsonBase, toBson]): BsonBase =
  (@args).toBson

proc bsonBinary*(binstr: string, subtype = stGeneric): BsonBase =
  BsonBinary(value: binstr.bytes, subtype: subtype, kind: bkBinary)

proc bsonBinary*(binseq: seq[byte], subtype = stGeneric): BsonBase =
  BsonBinary(value: binseq, subtype: subtype, kind: bkBinary)

proc newBson*(table = newOrderedTable[string, BsonBase](),
    stream: Stream = newStringStream()): BsonDocument =
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
  else:
    val = bsonNull()
  result = (key, val)

proc decode*(strbytes: string): BsonDocument =
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
  for t in table:
    tableres[t[0]] = t[1]
  BsonDocument(
    table: tableres,
    stream: newStringStream()
  )

template bsonFetcher(b: BsonBase, targetKind: BsonKind,
    inheritedType: typedesc, targetType: untyped): untyped =
  if b.kind != targetKind:
    raise BsonFetchError(msg: "Cannot convert $# to $#" %
      [$b.kind, $targetType])
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
  if b.kind != bkString:
    raise BsonFetchError(msg: fmt"""Cannot convert {b.kind} to string""")
  else:
    $(b as BsonString).value

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

when isMainModule:
  let hellodoc = newbson(
    [("hello", 100.toBson),
    ("array world", bsonArray("red", 50, 4.2)),
    ("hello world", "hello, 異世界".toBson)
  ])

  dump hellodoc
  let (hellolen, hellostr) = encode hellodoc
  let newdoc = newBson(
    table = newOrderedTable([
      ("hello", 100.toBson),
      ("hello world", "hello, 異世界".toBson),
      ("a percent of truth", 0.42.toBson),
      ("array world", bsonArray("red", 50, 4.2)),
      ("this is null", bsonNull()),
      ("now", getTime().toBson),
      ("_id", genOid().toBson)
    ]),
    stream = newFileStream("bsonimpl_encode.bson", mode = fmReadWrite)
  )
  let (_, newhelstr) = encode newdoc
  dump hellolen
  dump hellostr
  dump newdoc

  let revdoc = decode newhelstr
  echo "this is decoded"
  dump revdoc

  let hellofield = "hello"
  dump revdoc[hellofield].get.ofInt32
  doAssert revdoc[hellofield].get.ofInt == newdoc[hellofield].get.ofInt
  try:
    dump revdoc[hellofield].get.ofDouble
  except BsonFetchError:
    echo getCurrentExceptionMsg()

  if hellofield in revdoc and revdoc[hellofield].isSome:
    dump revdoc[hellofield].get.ofInt

  dump revdoc["this is null"]
  doAssert revdoc["this is null"].isNil
  doAssert revdoc["this is null"].get.isNil
  doAssert not revdoc[hellofield].get.isNil

  let macrodoc = bson({
    hello: 100,
    hello_world: "hello, 異世界",
    array_world: ["red", 50, 4.2],
    embedding: {
      "key 1": "nahaha",
      ok: true
    }
  })
  dump macrodoc
  doAssert macrodoc["embedding"].get.ofEmbedded is BsonDocument

  dump bson({})

  let simplearray = bson({fields: [{haha: "haha"}, 2, 4.3, "road"]})
  dump simplearray

  block:
    let arrayembed = bson({
      objects: [
        { q: 1, u: { "$set": { role_name: "ok" }}},
        { q: 2, u: { "$set": { key_name: "ok" }}},
        { q: 3, u: { "$set": { truth: 42 }}}
      ]
    })
    dump arrayembed
    doAssert arrayembed["objects"][2]["u"]["$set"]["truth"].ofInt32 == 42
    let q2: int32 = arrayembed["objects"][1]["q"]
    doAssert q2 == 2

    try:
      dump arrayembed["objects"]["hello"]
    except BsonFetchError:
      echo getCurrentExceptionMsg()
    try:
      dump arrayembed["objects"][4]
    except IndexError:
      echo getCurrentExceptionMsg()
    try:
      dump arrayembed["objects"][1]["q"]["hello"]
    except BsonFetchError:
      echo getCurrentExceptionMsg()
    try:
      dump arrayembed["objects"][0][3]
    except BsonFetchError:
      echo getCurrentExceptionMsg()

  let stringbin = "MwahahaBinaryGotoki"
  let testbinary = bson({
    dummy_binary: bsonBinary stringbin
  })
  let (_, tbencoded) = encode testbinary
  let dectestbin = decode tbencoded
  dump dectestbin
  doAssert dectestbin["dummy_binary"].get.
    ofBinary.stringbytes == stringbin

  let qrimg = readFile "qrcode-me.png"
  dump qrimg.len
  let pngbin = bson({
    "qr-me": bsonBinary qrimg
  })
  let (_, pngbinencode) = encode pngbin
  let pngdec = decode pngbinencode
  doAssert pngdec["qr-me"].get.ofBinary.stringbytes == qrimg

  block:
    let currtime = getTime().toUnix.uint32
    let timestampdoc = bson({
      timestamp: (0'u32, currtime)
    })
    dump timestampdoc
    let (_, timestampstr) = encode timestampdoc
    let timestampdec = decode timestampstr
    dump timestampdec
    let decurrtime = timestampdec["timestamp"].get.ofTimestamp[1]
    dump currtime
    dump decurrtime
    doAssert decurrtime == currtime

  block:
    # empty bson
    let empty = bson()
    dump empty
    empty.stream.setPosition 0
    let emptystr = empty.stream.readAll
    dump emptystr.len
    for c in emptystr:
      stdout.write c.ord, " "
    echo()
    doAssert empty.isNil

  block:
    let emptyarr = newBson(
      table = newOrderedTable([
        ("emptyarr", bsonArray())]),
      stream = newFileStream("emptyarr.bson", mode = fmReadWrite))
    dump emptyarr
    let (_, empstr) = encode emptyarr
    let empdec = decode empstr
    dump empdec
    doAssert empdec["emptyarr"].get.ofArray.len == 0

  block:
    let emptyarr = decode(readFile "emptyarr.bson")
    dump emptyarr
    doAssert emptyarr["emptyarr"].get.ofArray.len == 0

  block:
    # test mutable bson object
    var arrayembed = bson({
      objects: [
        { q: 1, u: { "$set": { role_name: "ok" }}},
        { q: 2, u: { "$set": { key_name: "ok" }}},
        { q: 3, u: { "$set": { truth: 42 }}}
      ]
    })
    dump arrayembed["objects"][0]["q"]

    # modify first elem object with key q to 5
    arrayembed.mget("objects").mget(0).mget("q") = 5
    dump arrayembed["objects"][0]["q"]
  
  block:
    include macroto_test
