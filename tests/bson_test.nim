import unittest, times, oids, streams, tables, os
import core/bson
import sugar

{.warning[UnusedImport]: off.}

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
    check hellodoc["hello"].get == 100
    check hellodoc["array world"].get.ofArray.len == 3
    check hellodoc["hello world"].get == isekai

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
    check newdoc["hello world"].get == isekai
    check newdoc["hello"].get == 100
    check newdoc["this is null"].isNil
    check newdoc["now"].get == currtime
    check newdoc["_id"].get == curroid
    check fileExists bsonFilename

  test "Encode bson":
    var num: int
    (num, newdocstr) = encode newdoc
    check num > 0

  test "Decode bson":
    nnewdoc = decode newdocstr
    check nnewdoc["hello"].get.ofInt == 100
    check nnewdoc["hello world"].get == isekai
    check nnewdoc["array world"].get.ofArray.len == 3
    check nnewdoc["this is null"].isNil
    check nnewdoc["now"].get.ofTime == newdoc["now"].get

  test "Throw incorrect conversion value and accessing field":
    expect(BsonFetchError):
      discard nnewdoc["hello"].get.ofDouble
    expect(UnpackError):
      discard nnewdoc["nonexistent-field"].get

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
    check dectestbin["dummy_binary"].get.
      ofBinary.stringbytes == stringbin

    let qrimg = readFile "tests/qrcode-me.png"
    let pngbin = bson({
      "qr-me": bsonBinary qrimg
    })
    let (_, pngbinencode) = encode pngbin
    let pngdec = decode pngbinencode
    check pngdec["qr-me"].get.ofBinary.stringbytes == qrimg

  test "Bson timestamp codec operations":
    let currtime = getTime().toUnix.uint32
    let timestampdoc = bson({
      timestamp: (0'u32, currtime)
    })
    let (_, timestampstr) = encode timestampdoc
    let timestampdec = decode timestampstr
    let decurrtime = timestampdec["timestamp"].get.ofTimestamp[1]
    check decurrtime == currtime

  test "Empty bson array codec and write to file":
    let emptyarr = newBson(
      table = newOrderedTable([
        ("emptyarr", bsonArray())]),
      stream = newFileStream("emptyarr.bson", mode = fmReadWrite))
    let (_, empstr) = encode emptyarr
    let empdec = decode empstr
    check empdec["emptyarr"].get.ofArray.len == 0
  test "Read empty bson array from file":
    let emptyarr = decode(readFile "emptyarr.bson")
    check emptyarr["emptyarr"].get.ofArray.len == 0
  
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
    check bjs["js"].get == jscode
    let (_, encstr) = encode bjs
    let bjsdec = decode encstr
    check bjsdec["js"].get.ofString == bjs["js"].get.ofString

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
    check otheb.name == theb["name"].get
    check otheb.str == theb["str"].get

  let outer1 = bson({
    outerName: "outer 1",
    sis: theb
  })
  test "Conversion with 1 level object":
    let oouter1 = outer1.to SSIntString
    check oouter1.outerName == outer1["outerName"].get
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
  })

  let ssis2 = outer1.to SSIntString
  test "Ref object with 1 level hierarchy":
    check ssis2.outerName == outer1["outerName"].get
    check ssis2.sis.name == outer1["sis"].get["name"]

  let s2sis = s2b.to S2IntString
  test "Multiple aliased field 1 level hierarchial object and" &
    "ref object and array and array object":
    check s2sis.sis1.name == s2b["sis1"].get["name"]
    check s2sis.sisref.name == s2b["sis1"].get["name"]
    check s2sis.sissref[0].name == s2b["sissref"].get[0]["name"]
    check s2sis.sissref2[0].str == s2b["sissref2"].get[0]["str"]
    check s2sis.district.string == s2b["district"].get
    check s2sis.dsis.SimpleIntString.str == s2b["dsis"].get["str"]
    check s2sis.dbar.Bar == s2b["dbar"].get
    check s2sis.dsisref.RSintString.str == s2b["dsisref"].get["str"]
    check s2sis.sqdbar.len == s2b["sqdbar"].get.ofArray.len
    check s2sis.sqdbar[0].Bar == s2b["sqdbar"].get[0]
    check s2sis.arrdbar.len == 2
    check s2sis.arrdbar[0].Bar == s2b["arrdbar"].get[0]
    check s2sis.arrsisref.len == 1
    check s2sis.arrsisref[0].str == s2b["arrsisref"].get[0]["str"]
    check s2sis.arrsisrefalias.len == 1
    check s2sis.arrsisrefalias[0].name == s2b["arrsisrefalias"].get[0]["name"]
    check s2sis.sissdist.len == s2b["sissdist"].get.ofArray.len
    check s2sis.sissdist[0].SimpleIntString.str == s2b["sissdist"].get[0]["str"]
    check s2sis.sissdistref.len == s2b["sissdistref"].get.ofArray.len
    check s2sis.sissdistref[0].RSintString.name == s2b["sissdistref"].get[0]["name"]
    check s2sis.arrsisrefdist.len == 1
    check s2sis.arrsisrefdist[0].SimpleIntString.str == s2b["arrsisrefdist"].get[0]["str"]
    check s2sis.arrsisdistref.len == 1
    check s2sis.arrsisdistref[0].RSintString.name == s2b["arrsisdistref"].get[0]["name"]
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
  let osob = bsob.to SeqOfBson
  test "Bypass when converting to BsonDocument object":
    check osob.label == bsob["label"].get
    check osob.documents[0]["field1"].get == bsob["documents"][0]["field1"].ofString
    check osob.documents[1]["fieldfield"].get == bsob["documents"][1]["fieldfield"].ofString

  type ManyTimes = object
    times: seq[Time]

  var btimes = bson({
    times: [currtime, currtime, currtime]
  })
  let otimes = btimes.to ManyTImes
  test "Seq of Time conversion object":
    check otimes.times[1] == currtime

  type
    TimeWrap = object
      time: Time
    OTimeWrap = object
      timewrap: TimeWrap

  let botw = bson({
    timewrap: { time: currtime },
  })
  let ootw = botw.to OTimeWrap
  test "Wrapped time conversion":
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
  let omo = bmo.to ManyObjects
  test "Many object wraps conversion":
    check omo.wrap.outerName == outer1["outerName"].get
    check omo.o3sis.oosis.sis.str == outer1["sis"]["str"]
    check omo.ootimewrap.otimewrap.timewrap.time == currtime