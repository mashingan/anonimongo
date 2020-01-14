
type
  Bar = string
  BarDistrict = distinct string
  DSIntString = distinct SimpleIntString
  DSisRef = distinct ref SimpleIntString
  DBar = distinct Bar
  RSintString = ref SimpleIntString

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
})

dump theb.to(SimpleIntString)
dump (theb.to(RSintString)).repr

let ssis2 = outer1.to SSIntString
dump ssis2
dump ssis2.sis.repr
doAssert ssis2.outerName == outer1["outerName"].get
doAssert ssis2.sis.name == outer1["sis"].get["name"]

let s2sis = s2b.to S2IntString
dump s2sis
dump s2sis.sis1
dump s2sis.sissref.repr
dump s2sis.sissref2.repr
dump s2sis.district.string
dump s2sis.dsis.SimpleIntString
dump s2sis.dbar.Bar
dump s2sis.dsisref.repr
dump seq[Bar](s2sis.sqdbar)
dump array[2, Bar](s2sis.arrdbar)
dump s2sis.arrsisref[0].repr
dump s2sis.arrsisrefalias[0].repr
dump seq[SimpleIntString](s2sis.sissdist)
dump RSintString(s2sis.sissdistref[0]).repr
dump SimpleIntString(s2sis.arrsisrefdist[0])
dump RSintString(s2sis.arrsisdistref[0]).repr
doAssert s2sis.sis1.name == s2b["sis1"].get["name"]
doAssert s2sis.sisref.name == s2b["sis1"].get["name"]
doAssert s2sis.district.string == s2b["district"].get