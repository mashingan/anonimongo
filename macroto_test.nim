
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
let outer1 = bson({
  outerName: "outer 1",
  sis: theb
})
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

#dump theb.to(SimpleIntString)
#dump (theb.to(RSintString)).repr

let ssis2 = outer1.to SSIntString
doAssert ssis2.outerName == outer1["outerName"].get
doAssert ssis2.sis.name == outer1["sis"].get["name"]

let s2sis = s2b.to S2IntString
doAssert s2sis.sis1.name == s2b["sis1"].get["name"]
doAssert s2sis.sisref.name == s2b["sis1"].get["name"]
doAssert s2sis.sissref[0].name == s2b["sissref"].get[0]["name"]
doAssert s2sis.sissref2[0].str == s2b["sissref2"].get[0]["str"]
doAssert s2sis.district.string == s2b["district"].get
doAssert s2sis.dsis.SimpleIntString.str == s2b["dsis"].get["str"]
doAssert s2sis.dbar.Bar == s2b["dbar"].get
doAssert s2sis.dsisref.RSintString.str == s2b["dsisref"].get["str"]
doAssert s2sis.sqdbar.len == s2b["sqdbar"].get.ofArray.len
doAssert s2sis.sqdbar[0].Bar == s2b["sqdbar"].get[0]
doAssert s2sis.arrdbar.len == 2
doAssert s2sis.arrdbar[0].Bar == s2b["arrdbar"].get[0]
doAssert s2sis.arrsisref.len == 1
doAssert s2sis.arrsisref[0].str == s2b["arrsisref"].get[0]["str"]
doAssert s2sis.arrsisrefalias.len == 1
doAssert s2sis.arrsisrefalias[0].name == s2b["arrsisrefalias"].get[0]["name"]
doAssert s2sis.sissdist.len == s2b["sissdist"].get.ofArray.len
doAssert s2sis.sissdist[0].SimpleIntString.str == s2b["sissdist"].get[0]["str"]
doAssert s2sis.sissdistref.len == s2b["sissdistref"].get.ofArray.len
doAssert s2sis.sissdistref[0].RSintString.name == s2b["sissdistref"].get[0]["name"]
doAssert s2sis.arrsisrefdist.len == 1
doAssert s2sis.arrsisrefdist[0].SimpleIntString.str == s2b["arrsisrefdist"].get[0]["str"]
doAssert s2sis.arrsisdistref.len == 1
doAssert s2sis.arrsisdistref[0].RSintString.name == s2b["arrsisdistref"].get[0]["name"]
doAssert s2sis.timenow == currtime
doAssert s2sis.dtimenow.Time == currtime

type
  NotHomogenousSeq = object
    theseq: seq[string]
try:
  dump bson({
    theseq: ["異世界", "hello", 4.2, 10]
  }).to NotHomogenousSeq
except BsonFetchError:
  echo "catched the expection: ", getCurrentExceptionMsg()

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
doAssert osob.label == bsob["label"].get
doAssert osob.documents[0]["field1"].get == bsob["documents"][0]["field1"]
doAssert osob.documents[1]["fieldfield"].get == bsob["documents"][1]["fieldfield"].ofString

type ManyTimes = object
  times: seq[Time]

var btimes = bson({
  times: [currtime, currtime, currtime]
})
let otimes = btimes.to ManyTImes
doAssert otimes.times[1] == currtime

type
  TimeWrap = object
    time: Time
  OTimeWrap = object
    timewrap: TimeWrap

let botw = bson({
  timewrap: { time: currtime },
})
let ootw = botw.to OTimeWrap
doAssert ootw.timewrap.time == currtime

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
doAssert omo.wrap.outerName == outer1["outerName"].get
doAssert omo.o3sis.oosis.sis.str == outer1["sis"]["str"]
doAssert omo.ootimewrap.otimewrap.timewrap.time == currtime

# test with skip pragma
type
  WithSkip = object
    skip: string
    get: BsonDocument
let bws = bson({
  skip: "won't be copied",
  get: {
    field1: "random",
    field2: 42,
    field3: 4.2,
  }
})
let ows = bws.to WithSkip
dump ows