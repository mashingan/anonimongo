{.experimental.}
import std/streams

type
  Readable* = concept r, type T
    proc read[T](r: Readable, x: var T)
    r.readFloat64 is float64
    r.readChar is char
    r.readInt8 is int8
    r.readInt32 is int32
    r.readInt64 is int64
    r.readStr(int) is string
    r.readUint32 is uint32
  Writable* = concept w, type T
    proc write[T](w: Writable, x: var T)
  Peekable* = concept p, type T
    proc peekStr(p: Peekable, n: int): string
    p.peekInt32 is int32
    p.peekChar is char
    p.peekInt8 is int8

  Streamable* {.explain.} = concept var s
    Readable
    Writable
    Peekable
    proc readAll(s: var Streamable): string
    proc atEnd(s: var Streamable): bool
    proc setPosition(s: var Streamable, n: int)
    proc getPosition(s: var Streamable): int

  DefaultStream* = object
    data: string
    pos: int
    length: int
    cap: int

const bufcap = 128

when defined(anostreamable):
  type MainStream* = DefaultStream
else:
  type MainStream* = Stream

proc write*[T](s: var DefaultStream, data: T) =
  template addcap =
    s.data &= newString(bufcap)
    s.cap += bufcap
  when sizeof(data) == 8 and data isnot string:
    if s.length+8 > s.cap: addcap()
    let datarr = cast[array[8, byte]](data)
    for i, b in datarr: s.data[s.pos+i] = chr b
    s.length += 8
    if s.length == 0: dec s.pos
    s.pos += 8
  elif sizeof(data) == 4 and data isnot string:
    if s.length+4 > s.cap: addcap()
    let datarr = cast[array[4, byte]](data)
    s.data &= newString(4)
    for i, b in datarr: s.data[s.pos+i] = chr b
    s.length += 4
    if s.length == 0: dec s.pos
    s.pos += 4
  elif data.type is char:
    if s.length + 1 > s.cap: addcap()
    s.data &= data
    inc s.length
    inc s.pos
  elif sizeof(data) == 1 and data isnot string:
    if s.length + 1 > s.cap: addcap()
    s.data &= chr data
    s.length += 1
    if s.length == 0: dec s.pos
    s.pos += 1
  elif data.type is string:
    let newlen = s.length + data.len
    var newcap = 0
    while s.cap < newlen:
      s.cap += bufcap
      newcap += bufcap
    s.data &= newString(newcap)
    s.data[s.pos ..< data.len] = data
    s.length = newlen
    if s.length == 0: dec s.pos
    s.pos += data.len

proc readAll*(s: var DefaultStream): string =
  result = s.data[s.pos ..< s.length]
  s.pos = s.length - 1

proc peekChar*(s: var DefaultStream): char =
  let thepos = min(s.pos, s.length-1)
  s.data[thepos]
proc peekInt8*(s: var DefaultStream): int8 =
  let thepos = min(s.pos, s.length-1)
  s.data[thepos].int8
proc peekInt32*(s: var DefaultStream): int32 =
  if s.pos+4 >= s.length: return int32.low
  var arr: array[4,  byte]
  for i, c in s.data[s.pos .. s.pos+3]: arr[i] = byte c
  cast[int32](arr)

proc peekStr*(s: var DefaultStream, n: int): string =
  s.data[s.pos ..< min(n, s.length-1)]

proc atEnd*(s: var DefaultStream): bool = s.pos >= s.length - 1

proc read*[T](s: var DefaultStream, data: var T) =
  when sizeof(data) == 8 and data isnot string:
    var datarr: array[8, byte]
    for i, c in s.data[s.pos .. s.pos+3]:
      datarr[i] = byte c
    data = cast[T](datarr)
    s.pos += 4
  elif sizeof(data) == 4 and data isnot string:
    var datarr: array[4, byte]
    for i, c in s.data[s.pos .. s.pos+1]:
      datarr[i] = byte c
    data = cast[T](datarr)
    s.pos += 2
  elif data.type is char:
    data = s.data[s.pos]
    inc s.pos
  elif data.type is string:
    let datalen = data.len
    if datalen == 0:
      data = s.data[s.pos ..< s.length]
      s.pos = s.length-1
    elif datalen > 0:
      let thelen = min(datalen, s.length)
      data = s.data[s.pos ..< thelen]
      s.pos += thelen

proc readFloat64*(s: var DefaultStream): float64 = s.read(result)
proc readInt64*(s: var DefaultStream): int64 = s.read(result)
proc readInt32*(s: var DefaultStream): int32 = s.read(result)
proc readUint32*(s: var DefaultStream): uint32 = s.read(result)
proc readInt8*(s: var DefaultStream): int8 = s.read(result)
proc readChar*(s: var DefaultStream): char = s.read(result)
proc readStr*(s: var DefaultStream, n: int): string =
  result = newString(n)
  s.read(result)

proc getPosition*(s: DefaultStream): int = s.pos
proc setPosition*(s: var DefaultStream, pos: int) = s.pos = min(pos, s.length-1)

proc newStream*(d = ""): MainStream =
  when not defined(anostreamable):
    newStringStream(d)
  else:
    var cap = bufcap
    var data = newString(cap)
    if d.len > cap:
      data = d
      let ncap = d.len div cap
      let rcap = d.len mod cap
      cap = if rcap == 0: ncap else: ncap+1
      data &= newString(bufcap - rcap)
    DefaultStream(
      data: data,
      pos: 0,
      length: d.len,
      cap: cap
    )

when isMainModule:
  import std/sugar

  proc echoStream(s: var Streamable) = echo s.readAll
  proc peak1(s: var Streamable): string = s.peekStr(1)

  var cs = newStream("hello world")
  dump cs is Readable
  dump cs is Writable
  dump cs is Peekable
  dump cs is Streamable
  echoStream(cs) {.explain.}
  cs.setPosition 0
  dump cs.peak1