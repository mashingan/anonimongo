import unittest, times, oids, streams, tables, os
import anonimongo/core/bson
import sugar

{.warning[UnusedImport]: off.}

const qrimg = readFile "tests/qrcode-me.png"

suite "Bson operations tests":
  let isekai = "hello, 異世界"
  let currtime = now().toTime
  let curroid = genOid()
  var newdoc: BsonDocument
  var nnewdoc: BsonDocument
  var newdocstr = ""
  var arrayembed = bson({
    objects: [
      { q: 1, u: { "$set": { role_name: "ok" }}},
      { q: 2, u: { "$set": { key_name: "ok" }}},
      { q: 3, u: { "$set": { truth: 42 }}}
    ]
  })
  test "Defining simple bson with newbson":
    let hellodoc = newbson(
      [("hello", 100.toBson),
      ("array world", bsonArray("red", 50, 4.2)),
      ("hello world", isekai.toBson)
    ])
    check hellodoc["hello"] == 100
    check hellodoc["array world"].ofArray.len == 3
    check hellodoc["hello world"] == isekai

  test "Defining bson with explicit table and writing to output stream":
    let bsonFilename = "bsonimpl_encode.bson"
    removeFile bsonFilename
    newdoc = newBson(
      table = newOrderedTable([
        ("hello", 100.toBson),
        ("hello world", isekai.toBson),
        ("a percent of truth", 0.42.toBson),
        ("array world", bsonArray("red", 50, 4.2)),
        ("this is null", bsonNull()),
        ("now", currtime.toBson),
        ("_id", curroid.toBson)
      ]),
      stream = newFileStream(bsonFilename, mode = fmReadWrite))
    check newdoc["hello world"] == isekai
    check newdoc["hello"] == 100
    check newdoc["this is null"].isNil
    check newdoc["now"] == currtime
    check newdoc["_id"] == curroid
    check fileExists bsonFilename

  test "Encode bson":
    var num: int
    (num, newdocstr) = encode newdoc
    check num > 0

  test "Decode bson":
    nnewdoc = decode newdocstr
    check nnewdoc["hello"].ofInt == 100
    check nnewdoc["hello world"] == isekai
    check nnewdoc["array world"].ofArray.len == 3
    check nnewdoc["this is null"].isNil
    check nnewdoc["now"].ofTime == newdoc["now"]

  test "Throw incorrect conversion value and accessing field":
    expect(BsonFetchError):
      discard nnewdoc["hello"].ofDouble
    expect(KeyError):
      discard nnewdoc["nonexistent-field"]

  test "Embedded bson document":
    check arrayembed["objects"][2]["u"]["$set"]["truth"].ofInt32 == 42
    let q2: int = arrayembed["objects"][1]["q"]
    check q2 == 2

    expect(BsonFetchError):
      discard arrayembed["objects"]["hello"]
    expect(IndexError):
      discard arrayembed["objects"][4]
    expect(BsonFetchError):
      discard arrayembed["objects"][1]["q"]["hello"]
    expect(BsonFetchError):
      discard arrayembed["objects"][0][3]

  test "Bson binary operations":
    require(fileExists "tests/qrcode-me.png")
    let stringbin = "MwahahaBinaryGotoki"
    let testbinary = bson({
      dummy_binary: bsonBinary stringbin
    })
    let (_, tbencoded) = encode testbinary
    let dectestbin = decode tbencoded
    check dectestbin["dummy_binary"].
      ofBinary.stringbytes == stringbin

    let pngbin = bson({
      "qr-me": bsonBinary qrimg
    })
    let (_, pngbinencode) = encode pngbin
    let pngdec = decode pngbinencode
    check pngdec["qr-me"].ofBinary.stringbytes == qrimg

  test "Bson timestamp codec operations":
    let currtime = getTime().toUnix.uint32
    let timestampdoc = bson({
      timestamp: (0'u32, currtime)
    })
    let (_, timestampstr) = encode timestampdoc
    let timestampdec = decode timestampstr
    let decurrtime = timestampdec["timestamp"].ofTimestamp[1]
    check decurrtime == currtime

  test "Empty bson array codec and write to file":
    let emptyarr = newBson(
      table = newOrderedTable([
        ("emptyarr", bsonArray())]),
      stream = newFileStream("emptyarr.bson", mode = fmReadWrite))
    let (_, empstr) = encode emptyarr
    let empdec = decode empstr
    check empdec["emptyarr"].ofArray.len == 0
  test "Read empty bson array from file":
    let emptyarr = decode(readFile "emptyarr.bson")
    check emptyarr["emptyarr"].ofArray.len == 0
  
  test "Mutable bson field access":
    check arrayembed["objects"][0]["q"] == 1

    # modify first elem object with key q to 5
    arrayembed.mget("objects").mget(0).mget("q") = 5
    check arrayembed["objects"][0]["q"] == 5

  test "Js code string bson":
    #test js code
    let jscode = "function double(x) { return x*2; }"
    let jsbson = bsonJs jscode
    let bjs = bson({
      js: jsbson,
    })
    check bjs["js"] == jscode
    let (_, encstr) = encode bjs
    let bjsdec = decode encstr
    check bjsdec["js"].ofString == bjs["js"].ofString

suite "Macro to object conversion tests":
  type
    Bar = string
    BarDistrict = distinct string
    DSIntString = distinct SimpleIntString
    DSisRef = distinct ref SimpleIntString
    DBar = distinct Bar
    RSintString = ref SimpleIntString
    DTime = distinct Time

    SimpleIntString = object
      name: int
      str: string
    
    SSIntString = object
      outerName: string
      sis: ref SimpleIntString

    S2IntString = object
      sis1: SimpleIntString
      sisref: ref SimpleIntString
      seqs: seq[string]
      siss: seq[SimpleIntString]
      sissref: seq[ref SimpleIntString]
      sissref2: seq[RSintString]
      sissdist: seq[DSIntString]
      sissdistref: seq[DSisRef]
      bar: Bar
      seqbar: seq[Bar]
      district: BarDistrict
      dsis: DSIntString
      dsisref: DSisRef
      dbar: DBar
      sqdbar: seq[DBar]
      arrbar: array[2, Bar]
      arrdbar: array[2, DBar]
      arrsis: array[1, SimpleIntString]
      arrsisref: array[1, ref SimpleIntString]
      arrsisrefalias: array[1, RSintString]
      arrsisrefdist: array[1, DSIntString]
      arrsisdistref: array[1, DSisRef]
      timenow: Time
      dtimenow: DTime
      anosis: SimpleIntString # no bson data
      aint: int
      abar: Bar
      adsis: DSIntString

  var theb = bson({
    name: 10,
    str: "hello 異世界"
  })
  test "Simple convertion bson to flat object":
    let otheb = theb.to SimpleIntString
    check otheb.name == theb["name"]
    check otheb.str == theb["str"]

  let outer1 = bson({
    outerName: "outer 1",
    sis: theb
  })
  test "Conversion with 1 level object":
    let oouter1 = outer1.to SSIntString
    check oouter1.outerName == outer1["outerName"]
    check oouter1.sis.name == outer1["sis"]["name"]
  let currtime = now().toTime
  let s2b = bson({
    sis1: theb,
    sisref: theb,
    seqs: ["hello", "異世界", "another world"],
    siss: [theb, theb],
    sissref: [theb, theb],
    sissref2: [theb, theb],
    sissdist: [theb, theb],
    sissdistref: [theb, theb],
    bar: "Barbar 勝利",
    seqbar: ["hello", "異世界", "another world"],
    district: "Barbar 勝利",
    dsis: {
      name: 15,
      str: "why the field is name but it's integer!?"
    },
    dsisref: {
      name: 15,
      str: "why the field is name but it's integer!?"
    },
    dbar: "Barbar 勝利",
    sqdbar: ["hello", "異世界", "another world"],
    arrbar: ["hello", "異世界", "another world"],
    arrdbar: ["hello", "異世界", "another world"],
    arrsis: [theb, theb],
    arrsisref: [theb, theb],
    arrsisrefalias: [theb, theb],
    arrsisrefdist: [theb, theb],
    arrsisdistref: [theb, theb],
    timenow: currtime,
    dtimenow: currtime,
    "not-exists-field": true,
  })

  var ssis2: SSIntString
  test "Ref object with 1 level hierarchy":
    ssis2 = outer1.to SSIntString
    check ssis2.outerName == outer1["outerName"]
    check ssis2.sis.name == outer1["sis"]["name"]

  var s2sis: S2IntString
  test "Multiple aliased field 1 level hierarchial object and" &
    "ref object and array and array object":
    s2sis = s2b.to S2IntString
    check s2sis.sis1.name == s2b["sis1"]["name"]
    check s2sis.sisref.name == s2b["sis1"]["name"]
    check s2sis.sissref[0].name == s2b["sissref"][0]["name"]
    check s2sis.sissref2[0].str == s2b["sissref2"][0]["str"]
    check s2sis.district.string == s2b["district"]
    check s2sis.dsis.SimpleIntString.str == s2b["dsis"]["str"]
    check s2sis.dbar.Bar == s2b["dbar"]
    check s2sis.dsisref.RSintString.str == s2b["dsisref"]["str"]
    check s2sis.sqdbar.len == s2b["sqdbar"].ofArray.len
    check s2sis.sqdbar[0].Bar == s2b["sqdbar"][0]
    check s2sis.arrdbar.len == 2
    check s2sis.arrdbar[0].Bar == s2b["arrdbar"][0]
    check s2sis.arrsisref.len == 1
    check s2sis.arrsisref[0].str == s2b["arrsisref"][0]["str"]
    check s2sis.arrsisrefalias.len == 1
    check s2sis.arrsisrefalias[0].name == s2b["arrsisrefalias"][0]["name"]
    check s2sis.sissdist.len == s2b["sissdist"].ofArray.len
    check s2sis.sissdist[0].SimpleIntString.str == s2b["sissdist"][0]["str"]
    check s2sis.sissdistref.len == s2b["sissdistref"].ofArray.len
    check s2sis.sissdistref[0].RSintString.name == s2b["sissdistref"][0]["name"]
    check s2sis.arrsisrefdist.len == 1
    check s2sis.arrsisrefdist[0].SimpleIntString.str == s2b["arrsisrefdist"][0]["str"]
    check s2sis.arrsisdistref.len == 1
    check s2sis.arrsisdistref[0].RSintString.name == s2b["arrsisdistref"][0]["name"]
    check s2sis.timenow == currtime
    check s2sis.dtimenow.Time == currtime

  type
    NotHomogenousSeq = object
      theseq: seq[string]
  test "Handle error when convert non homogenous seq/array":
    expect BsonFetchError:
      discard bson({
        theseq: ["異世界", "hello", 4.2, 10]
      }).to NotHomogenousSeq

  type
    SeqOfBson = object
      label: string
      documents: seq[BsonDocument]

  let bsob = bson({
    label: "fix-macro-to",
    documents:[
      {
        field1: "ok",
        field2: 2,
        field3: true,
      },
      {
        field3: 4,
        field0: [],
        fieldfield: "異世界",
        field5: 4.2
      }
    ]
  })
  var osob: SeqOfBson
  test "Bypass when converting to BsonDocument object":
    osob = bsob.to SeqOfBson
    check osob.label == bsob["label"]
    check osob.documents[0]["field1"] == bsob["documents"][0]["field1"].ofString
    check osob.documents[1]["fieldfield"] == bsob["documents"][1]["fieldfield"].ofString

  type ManyTimes = object
    times: seq[Time]

  var btimes = bson({
    times: [currtime, currtime, currtime]
  })
  var otimes: ManyTImes
  test "Seq of Time conversion object":
    otimes = btimes.to ManyTImes
    check otimes.times[1] == currtime

  type
    TimeWrap = object
      time: Time
    OTimeWrap = object
      timewrap: TimeWrap

  let botw = bson({
    timewrap: { time: currtime },
  })
  var ootw: OTimeWrap
  test "Wrapped time conversion":
    ootw = botw.to OTimeWrap
    check ootw.timewrap.time == currtime

  # many object wraps
  type
    OOOSSIntString = object
      ootimewrap: OOTimewrap
      oosis: SSIntString
    OOTimeWrap = object
      otimewrap: OTimeWrap
    ManyObjects = object
      wrap*: SSIntString
      ootimewrap*: OOTimewrap
      o3sis*: OOOSSintString
  var bmo = bson({
    wrap: outer1,
    ootimewrap: {
      otimewrap: botw,
    },
    o3sis: {
      ootimewrap: { otimewrap: botw },
      oosis: outer1,
    }
  })
  var omo: ManyObjects
  test "Many object wraps conversion":
    omo = bmo.to ManyObjects
    check omo.wrap.outerName == outer1["outerName"]
    check omo.o3sis.oosis.sis.str == outer1["sis"]["str"]
    check omo.ootimewrap.otimewrap.timewrap.time == currtime

  type
    BinaryWrap = object
      binary: string # binary string
      seqbyte: seq[byte]
  var bbwo = bson({
    binary: bsonBinary qrimg,
    seqbyte: bsonBinary qrimg
  })
  var obwo: BinaryWrap
  test "Bson binary conversion bytes string":
    obwo = bbwo.to BinaryWrap
    check obwo.binary.len == qrimg.len
    check obwo.binary == qrimg
    check obwo.seqbyte.len == qrimg.len
    check obwo.seqbyte.stringbytes == qrimg

  type
    OVKind = enum
      ovOne ovMany ovNone
    ObjectVariant = object
      case kind: OVKind
      of ovOne:
        theOnlyField: string
      of ovMany:
        manyField1: string
        intField: int
        embed: BsonDocument
      of ovNone:
        nil
  let
    bovOne = bson({ kind: "ovOne", theOnlyField: "got this" })
    bovMany = bson({
      kind: "ovMany",
      manyField1: "example of ovMany",
      intField: 42,
      embed: {},
    })
    bovNone = bson({ kind: "ovNone" })
  test "Test object variant conversion":
    # test for a single field variant
    let oovOne = bovOne.to ObjectVariant
    check oovOne.kind == ovOne
    check oovOne.theOnlyField == bovOne["theOnlyField"]
    # test for a none object variant
    let oovNone = bovNone.to ObjectVariant
    check oovNone.kind == ovNone
    # test for many fields
    let oovMany = bovMany.to ObjectVariant
    check oovMany.kind == ovMany
    check oovMany.manyField1 == bovMany["manyField1"]
    check oovMany.intField == 42
    check oovMany.embed.isNil
  
  type
    TableStringInt = Table[string, int]
  test "Conversion to Table should yield nothing":
    let
      correctbson = bson({ "1": 1, "2": 2, "3": 3, "4": 4 })
      #incorrectbson = bson({ "1": "one", "2": 2, "3": 3})
      tsi = correctbson.to TableStringInt