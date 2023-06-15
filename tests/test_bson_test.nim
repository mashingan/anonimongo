import unittest, times, oids, streams, tables, os, options
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
    when false:
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
    else:
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
      )
    check newdoc["hello world"] == isekai
    check newdoc["hello"] == 100
    check newdoc["this is null"].isNil
    check newdoc["now"] == currtime
    check newdoc["_id"] == curroid
    check newdoc["a percent of truth"] == 0.42
    when false:
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

  when not defined(anostreamable):
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

  test "Add element to bson array":
    let newobj = bson({
      q: 4, u: { "$set": { role_name: "add" }},
    })
    arrayembed.mget("objects").add newobj
    check arrayembed["objects"].len == 4
    check arrayembed["objects"][3]["q"].ofInt == newobj["q"]
    check arrayembed["objects"][3]["u"]["$set"]["role_name"] == "add"

    expect BsonFetchError:
      var bsonInt = 4.toBson
      bsonInt.add newobj

  test "Clear stream when Bson is modified":
    let baseCompare = bson {
      arr: [42, 42.0, true, "nanana"],
    }
    let (baseN, baseStr) = encode baseCompare
    var itemCompare = bson { arr: [] }
    check itemCompare["arr"].kind == bkArray
    check itemCompare["arr"].len == 0
    when not defined(anostreamable):
      var fileCompare = newBson(filename = "filetest.bson")
      fileCompare["arr"] = bsonArray()
      check fileCompare["arr"].kind == bkArray
      check fileCompare["arr"].len == 0

    # first encoding mutation
    template compareArr(b: var BsonDocument, val: BsonBase, notsame = true) =
      b.mget("arr").add val
      let (n, str) = encode b
      if notsame:
        check n != baseN
        check str != baseStr
      else:
        check n == baseN
        check str == baseStr
    itemCompare.compareArr(42)
    itemCompare.compareArr(42.0)
    itemCompare.compareArr(true)
    itemCompare.compareArr("nanana", notsame = false)
    when not defined(anostreamable):
      fileCompare.compareArr(42)
      fileCompare.compareArr(42.0)
      fileCompare.compareArr(true)
      fileCompare.compareArr("nanana", notsame = false)

    # change the value to test the `[]=`
    let newval = bsonArray(1, 1.2, true, false, now().toTime)
    itemCompare["new-key"] = newval
    let (itemN, itemStr) = encode itemCompare
    check itemStr != baseStr
    check itemN != baseN
    when not defined(anostreamable):
      fileCompare["new-key"] = newval
      let (fileN, fileStr) = encode fileCompare
      check fileStr != baseStr
      check fileN != baseN
      check itemStr == fileStr
      check itemN == itemN

  test "Clear stream for BsonDocument when fetched with mget":
    let baseObjCompare = bson {
      base: {
        field1: 42,
        field2: 42.0,
      },
    }
    let (baseObjN, baseObjStr) = encode baseObjCompare
    var mutObj = bson {
      base: {},
    }
    var (mutN, mutStr) = encode mutObj
    check mutN != baseObjN
    check mutStr != baseObjStr
    mutObj.mget("base")["field1"] = 42
    (mutN, mutStr) = encode mutObj
    check mutN != baseObjN
    check mutStr != baseObjStr
    mutObj.mget("base")["field2"] = 42.0
    (mutN, mutStr) = encode mutObj
    check mutN == baseObjN
    check mutStr == baseObjStr

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
      name*: int
      str*: string
    
    SSIntString = object
      outerName*: string
      sis*: ref SimpleIntString

    EmptyRef = ref object
      ssisref*: seq[RSintString]

    S2IntString = object
      sis1*: SimpleIntString
      sisref*: ref SimpleIntString
      seqs*: seq[string]
      siss*: seq[SimpleIntString]
      sissref*: seq[ref SimpleIntString]
      sissref2*: seq[RSintString]
      sissdist*: seq[DSIntString]
      sissdistref*: seq[DSisRef]
      bar*: Bar
      seqbar*: seq[Bar]
      district*: BarDistrict
      dsis*: DSIntString
      dsisref*: DSisRef
      dbar*: DBar
      sqdbar*: seq[DBar]
      arrbar*: array[2, Bar]
      arrdbar*: array[2, DBar]
      arrsis*: array[1, SimpleIntString]
      arrsisref*: array[1, ref SimpleIntString]
      arrsisrefalias*: array[1, RSintString]
      arrsisrefdist*: array[1, DSIntString]
      arrsisdistref*: array[1, DSisRef]
      timenow*: Time
      dtimenow*: DTime
      anosis*: SimpleIntString # no bson data
      aint*: int
      abar*: Bar
      adsis*: DSIntString
      emptyRef*: EmptyRef # no bson data
      pseudoEmptyRef*: EmptyRef # no bson data

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
    pseudoEmptyRef: {}
  })

  var ssis2: SSIntString
  test "Ref object with 1 level hierarchy":
    ssis2 = outer1.to SSIntString
    check ssis2.outerName == outer1["outerName"]
    check ssis2.sis.name == outer1["sis"]["name"]

  var s2sis: S2IntString
  test "Multiple aliased field 1 level hierarchial object and " &
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
    check s2sis.emptyRef == nil
    check s2sis.pseudoEmptyRef.ssisref.len == 0

  type
    NotHomogenousSeq = object
      theseq*: seq[string]
  test "Handle error when convert non homogenous seq/array":
    expect BsonFetchError:
      discard bson({
        theseq: ["異世界", "hello", 4.2, 10]
      }).to NotHomogenousSeq

  type
    SeqOfBson = object
      label*: string
      documents*: seq[BsonDocument]

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
    times*: seq[Time]

  var btimes = bson({
    times: [currtime, currtime, currtime]
  })
  var otimes: ManyTImes
  test "Seq of Time conversion object":
    otimes = btimes.to ManyTImes
    check otimes.times[1] == currtime

  type
    TimeWrap = object
      time*: Time
    OTimeWrap = object
      timewrap*: TimeWrap

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
      ootimewrap*: OOTimewrap
      oosis*: SSIntString
    OOTimeWrap = object
      otimewrap*: OTimeWrap
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
      binary*: string # binary string
      seqbyte*: seq[byte]
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
    EmbedObjectVariant = object
      field1*: int
      field2*: string
      truthy {.bsonExport.}: bool
    RefEmbedObjVariant = ref EmbedObjectVariant
    ObjectVariant = object
      baseField*: string
      baseInt*: int
      baseEmbed*: BsonDocument
      case kind*: OVKind
      of ovOne:
        theOnlyField*: string
      of ovMany:
        manyField1*: string
        intField*: int
        embed*: EmbedObjectVariant
        refembed*: RefEmbedObjVariant
      of ovNone:
        nil
    OuterObject = ref object
      variant {.bsonExport, bsonKey: "objectVariant".}: ObjectVariant
  test "Test object variant conversion":
    # our Bson data
    var bov = bson({
      baseField: "this is base string",
      baseInt: 3453,
      kind: "ovMany",
      manyField1: "example of ovMany",
      intField: 42,
      embed: {
        truthy: true,
      },
      refembed: {
        truthy: true,
      },
    })
    var outb = bson({ objectVariant: bov })

    # let's see if it's converted to OVKind ovMany
    var outer: OuterObject
    let objmany = bov.to ObjectVariant
    outer = outb.to OuterObject
    check objmany.kind == ovMany
    check objmany.baseField == bov["baseField"]
    check objmany.baseInt == bov["baseInt"]
    check objmany.embed.truthy
    check objmany.refembed.truthy
    check objmany.manyField1 == bov["manyField1"]
    check objmany.intField == bov["intField"]
    check outer.variant.kind == ovMany
    check outer.variant.baseField == "this is base string"
    check outer.variant.baseInt == 3453
    check outer.variant.baseEmbed.isNil

    # let's change the kind to "ovOne"
    let onlyFieldMsg = "this is dynamically added"
    bov["kind"] = "ovOne"
    bov["theOnlyField"] = onlyFieldMsg
    outb.mget("objectVariant")["kind"] = "ovOne"
    outb.mget("objectVariant")["theOnlyField"] = onlyFieldMsg
    let objone = bov.to ObjectVariant
    outer = outb.to OuterObject
    check objone.kind == ovOne
    check objone.baseField == bov["baseField"]
    check objone.theOnlyField == "this is dynamically added"
    check outer.variant.kind == ovOne
    check outer.variant.theOnlyField == onlyFieldMsg

    # lastly, convert to "ovNone"
    bov["kind"] = "ovNone"
    outb.mget("objectVariant")["kind"] = "ovNone"
    let objnone = bov.to ObjectVariant
    outer = outb.to OuterObject
    check objnone.kind == ovNone
    check outer.variant.kind == ovNone
  
  type
    TableStringInt = Table[string, int]
    TableRefStringInt = TableRef[string, int]
    CustomTable = TableRef[string, BsonBase]
    OuterTable = ref object
      field {.bsonKey: "embedWorking", bsonExport.}: CustomTable

  test "Conversion to Table/TableRef directly should yield nothing,\n" &
    "\tworkaround with alias type and custom proc/convert/func definition" &
    " ofAliasType":
    let
      correctbson = bson({ "1": 1, "2": 2, "3": 3, "4": 4 })
      incorrectbson = bson({ "1": "one", "2": 2, "3": 3})
      bobj = bson({
        field1: "this field is string",
        field2: 3453,
        really: true,
        embedWorking: {
          efield: "this is embed field string",
          eint: 7337,
        },
      })

    proc ofCustomTable(b: BsonBase): CustomTable =
      let doc = b.ofEmbedded
      result = newTable[string, BsonBase](doc.len)
      for k, v in doc:
        result[k] = v

    let
      tsi = correctbson.to TableStringInt
      intsi = incorrectbson.to TableStringInt
      tsiref = correctbson.to TableRefStringInt
      outer = bobj.to OuterTable
    
    check tsi.len == 0
    check tsiref.len ==  0
    check intsi.len == 0
    check outer[].field is TableRef
    check outer[].field["eint"] == 7337

  test "Implement a specific value extract with pattern of `of` & Typename " &
    "and custom pragma `bsonExport` to enable the conversion":
    type
      TimeRef = ref DTime
      DistinctTimeRef = distinct TimeRef
      DDTime = distinct DTime
      SimpleObject = object
        zawarudo*: Time
        timeOfReference {.bsonExport.}: TimeRef
        distinctTimeRef*: DistinctTimeRef
        ddTime {.bsonExport.}: DDTime
    proc ofTimeRef(b: BsonBase): TimeRef =
      let t = b.ofTime
      new result
      result[] = DTime t

    proc ofDDTime(b: BsonBase): DDTime =
      result = b.ofTime.DDTime

    let nao = now().toTime
    let bsonObj = bson({
      zawarudo: nao,
      timeOfReference: nao,
      distinctTimeRef: nao,
      ddTime: nao
    })
    let simpobj = bsonObj.to SimpleObject
    check simpobj.zawarudo == nao
    check simpobj.timeOfReference[].Time == nao
    check simpobj.distinctTimeRef.TimeRef[].Time == nao
    check simpobj.ddTime.Time == nao

  type
    CustomS2IntString = object
      simpleIntStr {.bsonExport, bsonKey:"sis1".}: SimpleIntString
      sref {.bsonExport, bsonKey: "sisref".}: ref SimpleIntString
      customSeqs {.bsonExport, bsonKey: "seqs".}: seq[string]
      customSiss {.bsonExport, bsonKey: "siss".}: seq[SimpleIntString]
      notfoundSissref {.bsonExport.}: seq[ref SimpleIntString]
      customArrdbar {.bsonExport, bsonKey: "arrdbar".}: array[2, DBar]
      customDTimenow* {.bsonKey: "dtimenow".}: DTime
  test "Extract custom key Bson defined with bsonKey pragma":
    let bobj = s2b.to CustomS2IntString
    check bobj.simpleIntStr.name == s2b["sis1"]["name"]
    check bobj.sref.name == s2b["sis1"]["name"]
    check bobj.customSeqs.len == 3
    check bobj.customSeqs[1] == s2b["seqs"][1]
    check bobj.customSiss.len == 2
    check bobj.customSiss[0].name == s2b["siss"][0]["name"]
    check bobj.notfoundSissref.len == 0
    check bobj.customArrdbar.len == 2
    check bobj.customArrdbar[1].Bar == s2b["arrdbar"][1]
    check bobj.customDTimenow.Time == s2b["dtimenow"]

  test "Conversion of inherited object and its fields":
    type
      BaseObject = object of RootObj
        baseint {.bsonExport.}: int
        basestr {.bsonExport.}: string
        basefloat {.bsonExport.}: float

      BaseAlias = BaseObject
      Alias2Base = BaseAlias

      AddEmbedBase = ref object of Alias2Base
        addEmbed {.bsonExport, bsonKey: "embed".}: BsonDocument

      AddIntBase = ref object of AddEmbedBase
        addInt {.bsonExport, bsonKey: "int".}: int

      LastDescent = ref object
        child*: AddIntBase

    let b = bson({
      embed: {
        embedint: 34973,
        embedstr: "eagle",
        embedfloat: 42.0,
      },
      baseint: 42,
      basestr: "five",
      basefloat: 11.11,
      `int`: 147,
    })
    let ld = bson({ child: b })

    let
      addembed = b.to AddEmbedBase
      addint = b.to AddIntBase
      thelast = ld.to LastDescent
    
    check addembed.basestr == b["basestr"]
    check addembed.addEmbed["embedstr"].ofString == b["embed"]["embedstr"]
    check addembed.baseint == b["baseint"]
    check addint.addInt == b["int"]
    check addint.addEmbed["embedstr"].ofString == b["embed"]["embedstr"]
    check addint.baseint == addembed.baseint
    check thelast.child.addInt == addint.addInt
    check thelast.child.basestr == addembed.basestr
    check thelast.child.addEmbed["embedstr"].ofString == "eagle"

  test "Ignore any Option and accept nil literal value":
    type
      Embedopt = object
        optint {.bsonExport.}: OptionalInt
        optstr {.bsonExport.}: Option[string]
      OptionalInt = Option[int]
      OptionalStr = Option[string]
      OptFields = ref object
        optint {.bsonExport.}: OptionalInt
        optstr {.bsonExport.}: OptionalStr
        optbool {.bsonExport.}: Option[bool]
        embedopt {.bsonExport.}: Embedopt

    let emb = bson {
      optint: 555,
      optstr: "SSS"
    }
    let b = bson {
      optint: 42,
      optstr: nil,
      optbool: false,
      embedopt: emb,
      null: nil,
    }

    proc ofOptionalInt(b: BsonBase): Option[int] =
      if b.kind == bkInt32: result = some b.ofInt
      else: result = none[int]()

    proc ofOptionalStr(b: Bsonbase): Option[string] =
      if b.kind == bkString: result = some b.ofString
      else: result = none[string]()

    let optobj = b.to OptFields
    check optobj[].optint.isSome
    check optobj[].optint.get == 42
    check optobj[].optstr.isNone
    check optobj[].optbool.isNone
    check optobj[].embedopt.optint.isSome
    check optobj[].embedopt.optint.get == 555
    check optobj[].embedopt.optstr.isNone
    check b["null"].kind == bkNull
    check b["null"].isNil

  test "No op when converting to BsonBase":
    type
      Flexible = object
        field1 {.bsonExport.}: BsonBase
        field2 {.bsonExport.}: BsonBase
        field3 {.bsonExport.}: BsonBase

    let
      nao = now().toTime
      b1 = bson {
        field1: 42,
        field2: "hello",
        field3: nil,
      }
      b2 = bson {
        field1: 42.0,
        field2: true,
        field3: b1,
      }
      b3 = bson {
        field1: nil,
        field2: nao,
      }
    var flex = b1.to Flexible
    check flex.field1 == 42
    check flex.field2 == "hello"
    check flex.field3.isNil

    flex = b2.to Flexible
    check flex.field1 == 42.0
    check flex.field2.ofBool
    check flex.field3["field1"] == 42
    check flex.field3["field3"].isNil

    flex = b3.to Flexible
    check flex.field1.isNil
    check flex.field2 == nao
    check flex.field3.isNil

  test "Enum conversion":
    type
      En1 = enum
        En1En1 = "en1 enum1"
        En1En2 = "en1 enum2"
        En1En3 = "en1 enum3"
      En2 = enum
        En2En1 = "en2 enum1"
        En2En2 = "en2 enum2"
        En2En3 = "en2 enum3"

      Enough = object
        en1ough*: En1
        en2ough*: En2
      EnObj = object
        enfield1*: En1
        enfield2*: En2
        enough*: Enough

    let ben = bson {
      enfield1: "en1 enum3",
      enfield2: "en2 enum2",
      enough: {
        en1ough: "en1 enum2",
        en2ough: "en2 enum3",
      },
    }

    let oen = ben.to EnObj
    check oen.enfield1 == En1En3
    check oen.enfield2 == En2En2
    check oen.enough.en1ough == En1En2
    check oen.enough.en2ough == En2En3