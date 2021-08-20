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

  Streamable* {.explain.} = concept s
    Readable
    Writable
    Peekable
    s.readAll is string
    s.atEnd is bool
    s.setPosition(int)
    s.getPosition is int

  DefaultStream* = ref object
    data: string
    pos: int
    length: int

proc write*[T](s: DefaultStream, data: T) =
  when sizeof(data) == 8 and data isnot string:
    let datarr = cast[array[8, byte]](data)
    s.data &= $datarr
    s.length += 4
  elif sizeof(data) == 4 and data isnot string:
    let datarr = cast[array[4, byte]](data)
    s.data &= $datarr
    s.length += 2
  elif data.type is char:
    s.data &= data
    inc s.length
  elif data.type is string:
    s.data &= data
    s.length += data.len

proc readAll*(s: DefaultStream): string =
  result = s.data[s.pos .. ^1]
  s.pos = s.length - 1

proc peekChar*(s: DefaultStream): char =
  let thepos = min(s.pos, s.length-1)
  s.data[thepos]
proc peekInt8*(s: DefaultStream): int8 =
  let thepos = min(s.pos, s.length-1)
  s.data[thepos].int8
proc peekInt32*(s: DefaultStream): int32 =
  if s.pos+4 >= s.length: return int32.low
  var arr: array[4,  byte]
  for i, c in s.data[s.pos .. s.pos+3]: arr[i] = byte c
  cast[int32](arr)

proc peekStr*(s: DefaultStream, n: int): string =
  s.data[s.pos ..< min(n, s.length-1)]

proc atEnd*(s: DefaultStream): bool = s.pos == s.length - 1

proc read*[T](s: DefaultStream, data: var T) =
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
      data = s.data[s.pos .. ^1]
      s.pos = s.length-1
    elif datalen > 0:
      let thelen = min(datalen, s.length)
      data = s.data[s.pos ..< thelen]
      s.pos += thelen

proc readFloat64*(s: DefaultStream): float64 = s.read(result)
proc readInt64*(s: DefaultStream): int64 = s.read(result)
proc readInt32*(s: DefaultStream): int32 = s.read(result)
proc readUint32*(s: DefaultStream): uint32 = s.read(result)
proc readInt8*(s: DefaultStream): int8 = s.read(result)
proc readChar*(s: DefaultStream): char = s.read(result)
proc readStr*(s: DefaultStream, n: int): string =
  result = newString(n)
  s.read(result)

proc getPosition*(s: DefaultStream): int = s.pos
proc setPosition*(s: DefaultStream, pos: int) = s.pos = max(pos, s.length-1)

proc newStream*(d = ""): Streamable =
  when not defined(anostreamable):
    newStringStream(d)
  else:
    DefaultStream(
      data: d,
      pos: 0,
      length: d.len
    )

# var sslib = newStringStream("hello world")
# dump sslib is Readable
# dump sslib is Writable
# dump sslib is Peekable
# dump sslib is Streamable
# echoStream sslib
# sslib.setPosition 0
# dump sslib.peak1

when isMainModule:
  import std/sugar

  proc echoStream(s: Streamable) = echo s.readAll
  proc peak1(s: Streamable): string = s.peekStr(1)

  var cs = newStream("hello world")
  dump cs is Readable
  dump cs is Writable
  dump cs is Peekable
  dump cs is Streamable
  echoStream(cs) {.explain.}
  cs.pos = 0
  dump cs.peak1