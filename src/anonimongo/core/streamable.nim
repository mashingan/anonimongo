{.experimental.}
import std/streams

type
  Readable* = concept r, type T
    proc read[T](r: Readable, x: var T)
    r.readFloat64 is float64
    r.readChar is char
    r.readInt8 is int8
    r.readUint8 is byte
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

const bufcap {.intdefine.} = 128

when defined(anostreamable):
  type MainStream* = DefaultStream
else:
  type MainStream* = Stream

template addcap(s: var DefaultStream) =
  s.data &= newString(bufcap)
  s.cap += bufcap

proc write*(s: var DefaultStream, data: string) =
  let addlen = s.pos + data.len
  var newcap = 0
  while s.cap <= addlen:
    s.cap += bufcap
    newcap += bufcap
  s.length = addlen
  s.data &= newString(newcap)
  for i, c in data: s.data[s.pos+i] = c
  s.pos += data.len

proc write*(s: var DefaultStream, data: char) =
  if s.pos + 1 > s.cap: addcap(s)
  s.data[s.pos] = data
  inc s.pos
  s.length = max(s.pos, s.length)

template datawrite[T](s: var DefaultStream, n: int, data: T) =
  if s.pos + n > s.cap: addcap(s)
  copyMem(addr s.data[s.pos], unsafeAddr data, n)
  s.pos += n
  s.length = max(s.pos, s.length)

proc write*[T](s: var DefaultStream, data: T) = s.datawrite(sizeof data, data)

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
  copyMem(addr result, addr s.data[s.pos], 4)

proc peekStr*(s: var DefaultStream, n: int): string =
  s.data[s.pos ..< min(n, s.length)]

proc atEnd*(s: var DefaultStream): bool = s.pos >= s.length

proc read*[T](s: var DefaultStream, data: var T) =
  template readata(n: static[int]) {.used.} =
    copyMem(addr data, addr s.data[s.pos], n)
    s.pos += n
  when data isnot string:
    readata sizeof(data)
  elif data is string:
    let datalen = data.len
    if datalen == 0:
      discard
    elif datalen > 0:
      let thelen = min(s.pos+datalen, s.length-1)
      data = s.data[s.pos ..< thelen]
      s.pos = thelen

proc readFloat64*(s: var DefaultStream): float64 = s.read(result)
proc readInt64*(s: var DefaultStream): int64 = s.read(result)
proc readInt32*(s: var DefaultStream): int32 = s.read(result)
proc readUint32*(s: var DefaultStream): uint32 = s.read(result)
proc readInt8*(s: var DefaultStream): int8 = s.read(result)
proc readUint8*(s: var DefaultStream): uint8 = s.read(result)
proc readChar*(s: var DefaultStream): char = s.read(result)
proc readStr*(s: var DefaultStream, n: int): string =
  result = newString(n)
  s.read(result)

proc getPosition*(s: DefaultStream): int =  s.pos
proc setPosition*(s: var DefaultStream, pos: int) = s.pos = min(pos, s.length)

proc newStream*(d = ""): MainStream =
  when not defined(anostreamable):
    newStringStream(d)
  else:
    var cap = bufcap
    var data = d
    if data.len < cap: data &= newString(cap - data.len)
    elif d.len > cap:
      let ncap = d.len div cap
      let rcap = d.len mod cap
      cap = bufcap * (if rcap == 0: ncap else: ncap+1)
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