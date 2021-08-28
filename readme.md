# Anonimongo - Another pure Nim Mongo driver

## Table of content

1. [Introduction](#Introduction)
2. [Examples](#examples) 

    - [Simple operations](#simple-operations)
    - [Authenticate](#authenticate)
    - [SSL URI connect](#ssl-uri-connect)
    - [Upload file to GridFS](#upload-file-to-gridfs)
    - [Bson examples](#bson-examples)
    - [Convert object to BsonDocument](#convert-object-to-bsondocument)
    - [Convert from Bson to object variant](#convert-from-bson-to-object-variant)
    - [Convert with custom key Bson](#convert-with-custom-key-bson)
    - [Convert Json to and Bson and vice versa](#convert-json-bson)
    - [Watching a collection](#watching-a-collection)
    - [Todolist app](#todolist-app)
    - [Upload-file](#upload-file)
    - [Benchmark examples](#benchmark-examples)

3. [Specific Mentions for Working with Bson](#working-with-bson)
4. [Install](#install)
5. [Implemented APIs](#implemented-apis)
6. [Caveats](#caveats)
7. [License](#license)


## Introduction
[Mongodb][1] is a document-based key-value database which emphasize in high performance read
and write capabilities together with many strategies for clustering, consistency, and availability.

Anonimongo is a driver for Mongodb developed using pure Nim. As library, it's developed to enable
developers to be able to access and use Mongodb in projects using Nim. Several implementad as
APIs for low-level which works directly with [Database][7] and higher level APIs which works with
[Collection][8]. Any casual user just have to access the [Collection API][9] directly instead of
working with various [Database operations][10].

The APIs are closely following [Mongo documentation][4] with a bit variant for `explain` API. Each supported
command for `explain` added optional string value to indicate the verbosity of `explain` command.  
By default, it's empty string which also indicate the command operations working without the need to
`explain` the queries. For others detailed caveats can be found [here](#caveats).

Almost all of the APIs are in asynchronous so the user must `await` or use `waitfor` if the
scope where it's called not an asynchronous function.  
Any API that insert/update/delete will return [WriteResult][wr-doc]. So the user can check
whether the write operation is successful or not with its field boolean `success` and the field
string `reason` to know what's the error message returned. However it's still throwing any other
error such as

* `MongoError` (the failure related to Database APIs and Mongo APIs),
* `BsonFetchError` (getting the wrong Bson type from BsonBase),
* `KeyError` (accessing non-existent key BsonDocument or embedded document in BsonBase),
* `IndexError` (accessing index more than BsonArray length or BsonBase that's actually BsonArray length),
* `IOError` (related to socket),
* `TimeoutError` (when connecting with `mongodb+srv` scheme URI)

which are raised by the underlying process. Those errors are indicating an err in the program flow hence elevated
on how the user handles them.  

[This page][5] (`anonimongo.html`) is the elaborate documentation. It also explains several
modules and the categories for those modules. [The index][6] also available.

[TOC](#table-of-content)
## Examples

### Simple operations

There are two ways to define Bson object (`newBson` and `bson`) but it's preferable use `bson`
as `newBson` is the low-level object definition. Users can roll-out their own operator like
in example below.  
For creating client, it's preferable to use `newMongo` overload with `MongoUri` argument because
the `MongoUri` overload has better support for various client options such as

+ `AppName` for identifying your application when connecting to Mongodb server.
+ `readPreference` which support `primary` (default), `primaryPreferred`, `secondary`, `secondaryPreferred`.
+ `w` (as write concern option).
+ `retryableWrites` which can be supplied with `false` (default) or `true`.
+ `compressors` which support list of compressor: `snappy` and `zlib`.
+ `authSource` that point which database we want to authenticate.  
This won't be used if in the `MongoUri` users provide the path to the database intended.  
So the database source in case of `MongoUri` `"mongodb://localhost:27017/not-admin?authSource=admin"` is `"not-admin"`.
+ `ssl` or `tls` which can be `false` (default if not using `mongodb+srv` scheme), or true (default if using `mongodb+srv` scheme).
+ `tlsInsecure`, `tlsAllowInvalidCertificates`, `tlsAllowInvalidHostnames`. Please refer to Mongodb documentation
as these 3 options have elaborate usage. In most cases, users don't have to bother about these 3 options.

All above options parameters are case-insensitive but the values are not because
Mongodb server is not accepting case-insensitive values.

```nim
import times
import anonimongo

var mongo = newMongo(poolconn = 16) # default is 64
if not waitFor mongo.connect:
  # default is localhost:27017
  quit "Cannot connect to localhost:27017"
var coll = mongo["temptest"]["colltest"]
let currtime = now().toTime()
var idoc = newseq[BsonDocument](10)
for i in 0 .. idoc.high:
  idoc[i] = bson {
    datetime: currtime + initDuration(hours = i),
    insertId: i
  }

# insert documents
let writeRes = waitfor coll.insert(idoc)
if not writeRes.success:
  echo "Cannot insert to collection: ", coll.name
else:
  echo "inserted documents: ", writeRes.n

let id5doc = waitfor coll.findOne(bson {
  insertId: 5
})
doAssert id5doc["datetime"] == currtime + initDuration(hours = 5)

# we define our own operator `!>` for this example only.
template `!>`(b: untyped): BsonDocument = bson(b)

# find one and modify, return the old document by default
let oldid8doc = waitfor coll.findAndModify(
  !>{ insertId: 8},
  !>{ "$set": { insertId: 80 }})

# find documents with combination of find which return query and one/all/iter
let query = coll.find()
query.limit = 5.int32 # limit the documents we'll look
let fivedocs = waitfor query.all()
doAssert fivedocs.len == 5

# let's iterate the documents instead of bulk find
# this iteration is bit different with iterating result
# from `query.all` because `query.iter` is returning `Future[Cursor]`
# which then the Cursor has `items` iterator.
var count = 0
for doc in waitfor query.iter:
  inc count
doAssert count == 5

# find one document, which newly modified
let newid8doc = waitfor coll.findOne(bson { insertId: 80 })
doAssert oldid8doc["datetime"].ofTime == newid8doc["datetime"]

# remove a document
let delStat = waitfor coll.remove(bson {
  insertId: 9,
}, justone = true)

doAssert delStat.success  # must be true if query success

doAssert delStat.kind == wkMany # remove operation returns
                                # the WriteObject result variant
                                # of wkMany which withhold the
                                # integer n field for n affected
                                # document in successfull operation

doAssert delStat.n == 1   # number of affected documents

# count all documents in current collection
let currNDoc = waitfor coll.count()
doAssert currNDoc == (idoc.len - delStat.n)

close mongo
```

### Authenticate

```nim
import anonimongo

var mongo = newMongo()
if not waitfor mongo.connect:
  quit "Cannot connect to localhost:27017"

# change to :SHA1Digest for SCRAM-SHA-1 mechanism
if not mongo.authenticate[:SHA256Digest](username, password):
  quit "Cannot login to localhost:27017"
close mongo

# Authenticating using URI
mongo = newMongo(MongoUri("mongodb://username:password@domain-host/admin"))
if not waitfor mongo.connect:
  quit "Cannot connect to domain-host"
if not waitfor mongo.authenticate[:SHA256Digest]():
  quit "Cannot login to domain-host"
close mongo
```

### SSL URI connect

```nim
# need to compile with -d:ssl option to enable ssl
import strformat
import anonimongo

let uriserver = "mongo://username:password@localhost:27017/"
let sslkey = "/path/to/ssl/key.pem"
let sslcert = "/path/to/ssl/cert.pem"
let urissl = &"{uriserver}?tlsCertificateKeyFile=certificate:{encodeURL sslcert},key:{encodeURL sslkey}"
let connectToAtlast = "mongo+srv://username:password@atlas-domain/admin"
let multipleHostUri = "mongo://uname:passwd@domain-1,uname:passwd@domain-2,uname:passwd@domain-3/admin"

# uri ssl connection
var mongo = newMongo(MongoUri urissl)
close mongo

# or for `mongo+srv` connection scheme
mongo = newMongo(MongoUri connectToAtlas)
close mongo

# for multipleHostUri
mongo = newMongo(MongoUri multipleHostUri)
close mongo

# custom DNS server and its port
# by default it's: `dnsserver = "8.8.8.8"` and `dnsport = 53`
mongo = newMongo(
  MongoUri connectToAtlas,
  dnsserver = "1.1.1.1",
  dnssport = 5000)
close mongo
```

In the [test_replication_sslcon.nim](tests/test_replication_sslcon.nim), there's example of emulated
[DNS server custom for `SRV`](tests/utils_replica.nim#L29-L92)
of DNS seedlist lookup. So the URI to connect is `localhost:5000` which in return replying with
`localhost:27018`, `localhost:27019` and `localhost:27020` as domain of replication set.

### Upload file to GridFS

```nim
# this time the server doesn't need SSL/TLS or authentication
# gridfs is useful when the file bigger than a document capsize 16 megabytes
import anonimongo

var mongo = newMongo()
doAssert waitfor mongo.connect
var grid = mongo["target-db"].createBucket() # by default, the bucket name is "fs"
let res = waitfor grid.uploadFile("/path/to/our/file")
if not res.success:
  echo "some error happened: ", res.reason

var gstream = waitfor grid.getStream("our-available-file")
let data = waitfor gstream.read(5.megabytes) # reading 5 megabytes of binary data
doAssert data.len == 5.megabytes
close gstream
close mongo
```

### Bson examples

```nim
import times
import anonimongo/core/bson # if we only need to work with Bson

var simple = bson({
  thisField: "isString",
  embedDoc: {
    embedField1: "unicodeこんにちは異世界",
    "type": "cannot use any literal or Nim keyword except string literal or symbol",
    `distinct`: true, # this is acceptable make distinct as symbol using `

    # the trailing comma is accepted
    embedTimes: now().toTime,
  },
  "1.2": 1.2,
  arraybson: [1, "hello", false], # heterogenous elements
})
doAssert simple["thisField"] == "isString"
doAssert simple["embedDoc"]["embedField1"] == "unicodeこんにちは異世界"

# explicit fetch when BsonBase cannot be automatically converted.
doAssert simple["embedDoc"]["distinct"].ofBool
doAssert simple["1.2"].ofDouble is float64

# Bson support object conversion too
type
  IntString = object
    field1*: int
    field2*: string

var bintstr = bson {
  field1: 1000,
  field2: "power-level"
}

let ourObj = bintstr.to IntString
doAssert ourObj.field1 == 1000
doAssert ourObj.field2 == "power-level"
```

### Convert object to BsonDocument

```nim
import anonimongo/core/bson

type
  Obj1 = object
    str: string
    `int`: int
    `float`: float

proc toBson(obj: Obj1): BsonDocument =
  result = bson()
  for k, v in obj.fieldPairs:
    result[k] = v

let obj1 = Obj1(
  str: "test",
  `int`: 42,
  `float`: 42.0
)
let obj1doc = obj1.toBson
doAssert obj1doc["str"] == obj1.str
doAssert obj1doc["int"] == obj1.`int`
doAssert obj1doc["float"] == obj1.`float`
```

The converting example above can be made generic like:

```nim
proc toBson[T: tuple | object](o: T): BsonDocument =
  result = bson()
  for k, v in o.fieldPairs:
    result[k] = v
```

But according to the `fieldPairs` documentation, it can only support
tuple and object so if the user is working with ref object, they can
only convert it manually.  
  
Above `toBson` snippet code can be modified to accomodate the `bsonKey` pragma
(starting from `v0.4.5`) to be:

```nim
import macros
import anonimongo/core/bson

proc toBson[T: tuple | object](o: T): BsonDocument:
  result = bson()
  for k, v in o.fieldPairs:
    when v.hasCustomPragma(bsonKey):
      var key = v.getCustomPragmaVal(bsonKey)
      result[key] = v # or v.toBson for explicit conversion
    else:
      result[k] = v # or v.toBson for explicit conversion
```


Check [tests](tests/) for more examples of detailed usages.  
Elaborate Bson examples and cases are covered in [bson_test.nim](tests/test_bson_test.nim)

### Convert from Bson to object variant

```nim
# Below example is almost the same with test code from
# `test_bson_test.nim` file in tests

import anonimongo/core/bson

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
var outb = bson { objectVariant: bov }

# let's see if it's converted to OVKind ovMany
var outer: OuterObject
let objmany = bov.to ObjectVariant
outer = outb.to OuterObject
doAssert objmany.kind == ovMany
doAssert objmany.baseField == bov["baseField"]
doAssert objmany.baseInt == bov["baseInt"]
doAssert objmany.embed.truthy
doAssert objmany.refembed.truthy
doAssert objmany.manyField1 == bov["manyField1"]
doAssert objmany.intField == bov["intField"]
doAssert outer.variant.kind == ovMany
doAssert outer.variant.baseField == "this is base string"
doAssert outer.variant.baseInt == 3453
doAssert outer.variant.baseEmbed.isNil

# let's change the kind to "ovOne"
let onlyFieldMsg = "this is dynamically added"
bov["kind"] = "ovOne"
bov["theOnlyField"] = onlyFieldMsg
outb.mget("objectVariant")["kind"] = "ovOne"
outb.mget("objectVariant")["theOnlyField"] = onlyFieldMsg
let objone = bov.to ObjectVariant
outer = outb.to OuterObject
doAssert objone.kind == ovOne
doAssert objone.baseField == bov["baseField"]
doAssert objone.theOnlyField == "this is dynamically added"
doAssert outer.variant.kind == ovOne
doAssert outer.variant.theOnlyField == onlyFieldMsg

# lastly, convert to "ovNone"
bov["kind"] = "ovNone"
outb.mget("objectVariant")["kind"] = "ovNone"
let objnone = bov.to ObjectVariant
outer = outb.to OuterObject
doAssert objnone.kind == ovNone
doAssert outer.variant.kind == ovNone
```

### Convert with Custom Key Bson

```nim
# This example will show to extract a specific Bson key
# check the test_bson_test.nim for elaborate bsonKey example
# Available since v0.4.5

import oids, times, macros
import anonimongo/core/bson

type
  SimpleIntString = object
    intfield {.bsonExport.}: int
    strfield*: string
  OidString = string # provided to enable our own custom conversion definition
  CustomObj = object
    # we retrieve the same "_id" into `id` and `idStr` with
    # `idStr` defined with specific conversion proc
    id {.bsonExport, bsonKey: "_id".}: Oid
    idStr {.bsonExport, bsonKey: "_id".}: OidString
    sis {.bsonExport, bsonKey: "sisEmbed".}: SimpleIntString
    currentTime {.bsonExport, bsonKey: "now".}: Time

proc ofOidString(b: BsonBase): OidString =
  echo "ofOidString is called"
  result = $b.ofObjectId


let bobj = bson({
  "_id": genOid(),
  sisEmbed: {
    intfield: 42,
    strfield: "forthy two"
  },
  now: now().toTime,
})

var cobj: CustomObj
expandMacros:
  cobj = bobj.to CustomObj

doAssert $cobj.id == $bobj["_id"].ofObjectId
doAssert cobj.idStr == $bobj["_id"].ofObjectId
doAssert $cobj.id == cobj.idStr
doAssert cobj.sis.strfield == bobj["sisEmbed"]["strfield"]
doAssert cobj.currentTime == bobj["now"]
```

### Convert Json Bson
It's often so handy to work directly between Json and Bson. As currently, there's no direct support for
converting directly Json to Bson and vice versa. However this snippet example will come useful for generic
conversion between Json and Bson. This snippet example needs the Anonimongo since `v0.4.8`
(patch for working with `BsonArray`).


```nim
import json, times

import anonimongo/core/bson

let jsonobj = %*{
  "businessName":"TEST",
  "businessZip":"55555",
  "arr": [1, 2, 3, 4]
}

proc toBson(j: JsonNode): BsonDocument

proc convertElem(v: JsonNode): BsonBase =
  case v.kind
  of JInt: result = v.getInt
  of JString: result = v.getStr
  of JFloat: result = v.getFloat
  of JObject: result = v.toBson
  of JBool: result = v.getBool
  of JNull: result = bsonNull()
  of JArray:
    var arrval = bsonArray()
    for elem in v:
      arrval.add elem.convertElem
    result = arrval

proc toBson(j: JsonNode): BsonDocument =
  result = bson()
  for k, v in j:
    result[k] = v.convertElem

let bobj = jsonobj.toBson
doAssert bobj["businessName"] == jsonobj["businessName"].getStr
doAssert bobj["businessZip"] == jsonobj["businessZip"].getStr
doAssert bobj["arr"].len == jsonobj["arr"].len

proc toJson(b: BsonDocument): JsonNode

proc convertElem(v: BsonBase): JsonNode =
  case v.kind
  of bkInt32, bkInt64: result = newJInt v.ofInt
  of bkString: result = newJString v.ofString
  of bkBinary: result = newJString v.ofBinary.stringbytes
  of bkBool: result = newJBool v.ofBool
  of bkDouble: result = newJFloat v.ofDouble
  of bkEmbed: result = v.ofEmbedded.toJson
  of bkNull: result = newJNull()
  of bkTime: result = newJString $v.ofTime
  of bkArray:
    var jarray = newJArray()
    for elem in v.ofArray:
      jarray.add elem.convertElem
    result = jarray
  else:
    discard

proc toJson(b: BsonDocument): JsonNode =
  result = newJObject()
  for k, v in b:
    result[k] = v.convertElem

let jobj = bobj.toJson
doAssert jobj["businessName"].getStr == jsonobj["businessName"].getStr
doAssert jobj["businessZip"].getStr == jsonobj["businessZip"].getStr
doAssert jobj["arr"].len == jsonobj["arr"].len
```


Above example we convert the `jsonobj` (`JsonNode`) to `bobj` (`BsonDocument`)
and convert again from `bobj` to `jobj` (`JsonNode`). This should be useful
for most cases of working with Bson and Json.

### Watching a collection
This example is the example of changeStream operation. In this example we will
watch a collection and print the change to the console. It will stop when
there's `delete` or collection `drop` operation.

```nim
import sugar
import anonimongo

## watching feature can only be done to the replica set Mongodb server so users
## need to run the available replica set first

proc main =
  var mongo = newMongo(
    MongoUri "mongodb://localhost:27018,localhost:27019,localhost27020/admin"
    poolconn = 2)
  defer: close mongo

  if not waitfor mongo.connect:
    echo "failed to connect, quit"
    return

  var cursor: Cursor
  let db = mongo["temptest"]

  # we are create the collection explicitly
  dump waitfor db.create("templog")

  # the namespace will be `temptest.templog`
  let coll = db["templog"]

  # we try to watch the collection, there's possible error
  # for example the collection is not in replica set database,
  # or the invalid options, in this example we simply do nothing
  # to handle the error except printing it out to the screen
  try:
    cursor = waitfor coll.watch()
  except MongoError:
    echo "cannot watch the cursor"
    echo getCurrentExceptionMsg()
    return

  var lastChange: ChangeStream

  # we define our callback for how we're going to handle it,
  # in this example we dump the change info to the screen
  # and using the closure to assign the value to the
  # `lastChange` variable
  # With `stopWhen = {csDelete, csDrop}`, the loop of watch
  # will break when there's delete operation or the collection
  # is dropped.
  # note that in the current example, we just only want to
  # watch the collection so we `waitFor` it to end, in case
  # we want to do the other thing we can run the `cursor.forEach`
  # in the background.
  waitFor cursor.forEach(
    proc(cs: ChangeStream) = dump cs; lastChange = cs,
    stopWhen = {csDelete, csDrop})

  dump lastChange
  #doAssert lastChange.operationType == csDelete
  dump waitfor coll.drop

main()
```

### Todolist App

Head over to [Todolist Example](examples/todolist).

### Upload-file

Check [Upload-file Example](examples/uploadfile).

### Benchmark Examples

Various examples while benchmarking [here](examples/benchmark).


[TOC](#table-of-content)

## Working with Bson

Bson module has some functionalities to convert to and from the Object. However there are
some points to be aware:

1. The `to` macro is working exlusively converting object typedesc converting basic types already
supplied with `ofType` (with `Type` is `Int|Int32|Int64|Double|String|Time|Embedded|ObjectId`).

2. User can provide the custom proc, func, or converter with pattern of `of{Typename}` which
accepting a `BsonBase` and return `Typename`. For example:

```nim
import macros
import anonimongo/core/bson

type
  Embedtion = object
    embedfield*: int
    embedstat*: string
    wasProcInvoked: bool
  SimpleEmbedObject = object
    intfield*: int
    strfield*: string
    embed*: Embedtion

proc ofEmbedtion(b: BsonBase): Embedtion =
  let embed = b.ofEmbedded
  result.embedfield = embed["embedfield"]
  result.embedstat = embed["embedstat"]
  result.wasProcInvoked = true

let bsimple = bson({
  intfield: 42,
  strfield: "that's 42",
  embed: {
    embedfield: 42,
    embedstat: "42",
  },
})
var simple: SimpleEmbedObject
expandMacros:
  simple = bsimple.to SimpleEmbedObject
doAssert simple.intfield == 42
doAssert simple.strfield == "that's 42"
doAssert simple.embed.embedfield == 42
doAssert simple.embed.embedstat == "42"
doAssert simple.embed.wasProcInvoked
```

Note that the conversion `to` `SimpleEmbedObject` with `ofSimpleEmbedObject` custom proc,
func, or converter isn't checked as it becomes meaningless to use `to` macro
when the user can simply calling it directly. So any most outer type won't check whether
the user provides `of{MostOuterTypename}` implementation or not.

3. Auto Bson to Type conversion can only be done to the fields that are exported or
has custom pragma `bsonExport` as shown in this [example](#convert-from-bson-to-object-variant).

4. ~It potentially breaks when there's some arbitrary hierarchy of types definition. While it can handle
any deep of `distinct` types (that's distinct of distinct of distinct of .... of Type), but this
should be indication of some broken type definition and better be remedied from
the type design itself. If user thinks otherwise, please report this issue with the example code.~  
As with v2 of `to` macro, the conversion of arbitrary `ref` and `distinct` is supported. It cannot support the
`ref distinct Type` as it's not making any sense but it supports the `distinct ref Type`. Please report the issue
if user finds the otherwise.

5. In case the user wants to persist with the current definition of any custom deep of `distinct` type,
user should define the custom mechanism mentioned in point #1 above.

6. With `v0.4.5`, users are able to extract custom Bson key to map with specific field name by supplying the pragma
`bsonKey` e.g. `{.bsonKey: "theBsonKey".}`. Refer to the example [above](#convert-with-custom-key-bson). The key is **case-sensitive**.

7. `to` macro doesn't support for cyclic object types.

8. As mentioned in point #1, the `to` macro is working exclusively converting the defined object type. As
pointed out that here, [issue/10](https://github.com/mashingan/anonimongo/issues/10), `to` make it generic, it's
reasonable for uniformed `to` convert any `typedesc`. Because the `ofType` variants for basic types are implemented
as `converters`, it's easy for user to supply the `to` overload:

```nim
template to(b: BsonBase, name: typedesc): untyped =
  var r: name = b
  move r
```

There's no plan to add this snippet to the library but it maybe changed in later version.

9. Any form of field type `Option[T]` is ignored. Refer to point #2 (defining the users `ofTypename`)
to support automatic conversion. For example, the Bson field we received can have `int` or `null` so
we implement it:

```nim
type
  # note that we need an intermediate alias type name as `to` only knows
  # the symbol for custom proc conversion.
  OptionalInt = Option[int]
  TheObj = object
    optint {.bsonExport.}: OptionalInt
    optstr {.bsonExport.}: Option[string]

let intexist = bson {
  optint: 42,
  optstr: "this will be ignored",
}
let intnull = bson {
  optint: bsonNull(),
  optstr: "not converted",
}

proc ofOptionalInt(b: BsonBase): Option[int] =
  if b.kind == bkInt32: result = some b.ofInt
  else: result = none[int]()
  # or we can
  # elif b.kind == bkNull: result = none[int]()
  # just for clarity that it can have BsonInt32 or BsonNull
  # as its value from Bson

let
  haveint = intexist.to TheObj
  noint = intnull.to TheObj

doAssert haveint.optint.isSome
doAssert haveint.optint.get == 42
doAssert haveint.optstr.isNone
doAssert noint.optint.isNone
doAssert noint.optstr.isNone
```

10. Conversion to generic object and generic field type are not tested. Very likely it will break
the whole `to` conversion.

11. Object fields conversion doesn't support when the fields are grouped together, for example:

```nim
type
  SStr = object
    ss1*, ss2*: string

  SOkay = object
    ss1*: string
    ss2*: string

let bstr = bson {
  ss1: "string 1",
  ss2: "string 2",
}

# The compiler will complain that "node" has no type.
let sstr = bstr.to SStr

# This works because the `ss1` and `ss2` aren't grouped together
let sokay = bstr.to SOkay
```

Since each field can have differents pragma definition, it's always preferable to define
each field as its own.

[TOC](#table-of-content)

## Install

Anonimongo requires minimum Nim version of `v1.2.0`.  

For installation, we can choose several methods will be mentioned below.

Using Nimble package:

```
nimble install anonimongo
```

Or to install it locally

```
git clone https://github.com/mashingan/anonimongo
cd anonimongo
nimble develop
```

or directly from Github repo

```
nimble install https://github.com/mashingan/anonimongo 
```

to install the `#head` branch

```
nimble install https://github.com/mashingan/anonimongo@#head
#or
nimble install anonimongo@#head
```

The code in `#head` is always in tagged version. Untagged `#head` master branch
is usually only changes in something unrelated to the code itself.

### For dependency

```
requires "anonimongo"
```

or directly from Github repo

```
requires "https://github.com/mashingan/anonimongo"
```

[TOC](#table-of-content)
## Implemented APIs
This implemented APIs for Mongo from [Mongo reference manual][2]
and [mongo spec][3].

### Features connection

- :heavy_check_mark: URI connect
- :heavy_check_mark: Multiquery on URI connect
- :heavy_check_mark: Multihost on URI connect
- :white_square_button: Multihost on simple connect
- :heavy_check_mark: SSL/TLS connection
- :heavy_check_mark: SCRAM-SHA-1 authentication
- :heavy_check_mark: SCRAM-SHA-256 authentication
- :heavy_check_mark: `isMaster` connection
- :heavy_check_mark: `TailableCursor` connection
- :heavy_check_mark: `SlaveOk` operations
- :heavy_check_mark: Compression connection
- :heavy_check_mark: Retryable writes
- :white_square_button: Retryable reads
- :white_square_button: Sessions

### Features commands

#### :white_check_mark: Aggregation commands 4/4 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-aggregation/) [Anonimongo module](src/anonimongo/dbops/aggregation.nim)

- :heavy_check_mark: `aggregate` (collection procs: [`aggregate`](/src/anonimongo/collections.nim#L283))
- :heavy_check_mark: `count` (collection procs: [`count`](/src/anonimongo.collections.nim#L231))
- :heavy_check_mark: `distinct` (collection procs: [`distinct`](/src/anonimongo.collections.nim#L267))
- :heavy_check_mark: `mapReduce`


#### :white_check_mark: Geospatial command 1/1 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-geospatial/) [Anonimongo module](src/anonimongo/dbops/geospatial.nim#L109)

- :heavy_check_mark: `geoSearch`


#### :white_check_mark: Query and write operations commands 7/7 (<del>8</del>) [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-crud/) [Anonimongo module](src/anonimongo/dbops/crud.nim)

- :heavy_check_mark: `delete` (collection procs: [`remove`](/src/anonimongo/collections.nim#L167), [`remove`](/src/anonimongo/collections.nim#L179), [`remove`](/src/anonimongo/collections.nim#L199))
- :heavy_check_mark: `find` (collection procs: [`find`](/src/anonimongo/collections.nim#L99), [`findOne`](/src/anonimongo/collections.nim#L103), [`findAll`](/src/anonimongo/collections.nim#L109), [`findIter`](/src/anonimongo/collections.nim#L116))
- :heavy_check_mark: `findAndModify` (collection procs: [`findAndModify`](/src/anonimongo/collections.nim#L122))
- :heavy_check_mark: `getMore`
- :heavy_check_mark: `insert` (collection procs: [`insert`](/src/anonimongo/collections.nim#L211))
- :heavy_check_mark: `update` (collection procs: [`update`](/src/anonimongo/collections.nim#L143))
- :heavy_check_mark: `getLastError`
- :white_square_button: `resetError` (deprecated)


#### :x: Query plan cache commands 0/6 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-plan-cache/) <del>Anonimongo module</del>

- :white_square_button: `planCacheClear`
- :white_square_button: `planCacheClearFilters`
- :white_square_button: `planCacheListFilters`
- :white_square_button: `planCacheListPlans`
- :white_square_button: `planCacheListQueryShapes`
- :white_square_button: `planCacheSetFilter`


#### :ballot_box_with_check: Database operations commands 1/3 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-authentication/) [Anonimongo module](src/anonimongo/core/types.nim#L511)

- :heavy_check_mark: `authenticate`, implemented as Mongo proc. ([`authenticate`](src/anonimongo/core/types.nim#L511), [`authenticate`](src/anonimongo/core/types.nim#L519))
- :white_square_button: `getnonce`
- :white_square_button: `logout`

#### :white_check_mark: User management commands 7/7 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-user-management/) [Anonimongo module](src/anonimongo/dbops/client.nim)

- :heavy_check_mark: `createUser`
- :heavy_check_mark: `dropAllUsersFromDatabase`
- :heavy_check_mark: `dropUser`
- :heavy_check_mark: `grantRolesToUser`
- :heavy_check_mark: `revokeRolesFromUser`
- :heavy_check_mark: `updateUser`
- :heavy_check_mark: `usersInfo`

#### :white_check_mark: Role management commands 10/10 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-role-management/) [Anonimongo module](src/anonimongo/dbops/rolemgmt.nim)

- :heavy_check_mark: `createRole`
- :heavy_check_mark: `dropRole`
- :heavy_check_mark: `dropAllRolesFromDatabase`
- :heavy_check_mark: `grantPrivilegesToRole`
- :heavy_check_mark: `grantRolesToRole`
- :heavy_check_mark: `invalidateUserCache`
- :heavy_check_mark: `revokePrivilegesFromRole`
- :heavy_check_mark: `rovokeRolesFromRole`
- :heavy_check_mark: `rolesInfo`
- :heavy_check_mark: `updateRole`


#### :white_check_mark: Replication commands 12/12(<del>13</del>) [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-replication/) [Anonimongo module](src/anonimongo/dbops/replication.nim)

- :white_square_button: `applyOps` (internal command)
- :heavy_check_mark: `isMaster`
- :heavy_check_mark: `replSetAbortPrimaryCatchUp`
- :heavy_check_mark: `replSetFreeze`
- :heavy_check_mark: `replSetGetConfig`
- :heavy_check_mark: `replSetGetStatus`
- :heavy_check_mark: `replSetGetStatus`
- :heavy_check_mark: `replSetInitiate`
- :heavy_check_mark: `replSetMaintenance`
- :heavy_check_mark: `replSetReconfig`
- :heavy_check_mark: `replSetResizeOplog`
- :heavy_check_mark: `replSetStepDown`
- :heavy_check_mark: `replSetSyncFrom`

#### :x: Sharding commands 0/27 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-sharding/) <del>Anonimongo module</del>

- :white_square_button: `addShard`
- :white_square_button: `addShardToZone`
- :white_square_button: `balancerStart`
- :white_square_button: `balancerStop`
- :white_square_button: `checkShardingIndex`
- :white_square_button: `clearJumboFlag`
- :white_square_button: `cleanupOrphaned`
- :white_square_button: `enableSharding`
- :white_square_button: `flushRouterConfig`
- :white_square_button: `getShardMap`
- :white_square_button: `getShardVersion`
- :white_square_button: `isdbgrid`
- :white_square_button: `listShard`
- :white_square_button: `medianKey`
- :white_square_button: `moveChunk`
- :white_square_button: `movePrimary`
- :white_square_button: `mergeChunks`
- :white_square_button: `removeShard`
- :white_square_button: `removeShardFromZone`
- :white_square_button: `setShardVersion`
- :white_square_button: `shardCollection`
- :white_square_button: `shardCollection`
- :white_square_button: `split`
- :white_square_button: `splitChunk`
- :white_square_button: `splitVector`
- :white_square_button: `unsetSharding`
- :white_square_button: `updateZoneKeyRange`

#### :x: Session commands 0/8 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-sessions/) <del>Anonimongo module</del>

- :white_square_button: `abortTransaction`
- :white_square_button: `commitTransaction`
- :white_square_button: `endSessions`
- :white_square_button: `killAllSessions`
- :white_square_button: `killAllSessionByPattern`
- :white_square_button: `killSessions`
- :white_square_button: `refreshSessions`
- :white_square_button: `startSession`

#### :ballot_box_with_check: Administration commands 13/28 (<del>29</del>) [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-administration/) [Anonimongo module](src/anonimongo/dbops/admmgmt.nim)

- :white_square_button: `clean` (internal namespace command)
- :white_square_button: `cloneCollection`
- :white_square_button: `cloneCollectionAsCapped`
- :white_square_button: `collMod`
- :white_square_button: `compact`
- :white_square_button: `connPoolSync`
- :white_square_button: `convertToCapped`
- :heavy_check_mark: `create`
- :heavy_check_mark: `createIndexes` (collection proc: [`createIndexes`](src/anonimongo/collections.nim#L248))
- :heavy_check_mark: `currentOp`
- :heavy_check_mark: `drop`
- :heavy_check_mark: `dropDatabase`
- :white_square_button: `dropConnections`
- :heavy_check_mark: `dropIndexes` (collection procs: [`dropIndex`](src/anonimongo/collections.nim#L275), [`dropIndexes`](src/anonimongo/collections.nim#L275))
- :white_square_button: `filemd5`
- :white_square_button: `fsync`
- :white_square_button: `fsyncUnlock`
- :white_square_button: `getParameter`
- :heavy_check_mark: `killCursors`
- :heavy_check_mark: `killOp`
- :heavy_check_mark: `listCollections`
- :heavy_check_mark: `listDatabases`
- :heavy_check_mark: `listIndexes` (collection proc: [`listIndexes`](src/anonimongo/collections.nim#L264))
- :white_square_button: `logRotate`
- :white_square_button: `reIndex`
- :heavy_check_mark: `renameCollection`
- :white_square_button: `setFeatureCompabilityVersion`
- :white_square_button: `setParameter`
- :heavy_check_mark: `shutdown`

#### :white_check_mark: Diagnostic commands 17/17 (<del>26</del>) [Mongo module](https://docs.mongodb.com/manual/reference/command/nav-diagnostic/) [Anonimongo module](src/anonimongo/dbops/diagnostic.nim)

- :white_square_button: `availableQueryOptions` (internal command)
- :heavy_check_mark: `buildInfo`
- :heavy_check_mark: `collStats`
- :heavy_check_mark: `connPoolStats`
- :heavy_check_mark: `connectionStatus`
- :white_square_button: `cursorInfo` (removed, use metrics.cursor from `serverStatus` instead)
- :heavy_check_mark: `dataSize`
- :heavy_check_mark: `dbHash`
- :heavy_check_mark: `dbStats`
- :white_square_button: `diagLogging` (removed, on Mongo 3.6, use mongoreplay instead)
- :white_square_button: `driverOIDTest` (internal command)
- :heavy_check_mark: `explain`
- :white_square_button: `features` (internal command)
- :heavy_check_mark: `getCmdLineOpts`
- :heavy_check_mark: `getLog`
- :heavy_check_mark: `hostInfo`
- :white_square_button: `isSelf` (internal command)
- :heavy_check_mark: `listCommands`
- :white_square_button: `netstat` (internal command)
- :heavy_check_mark: `ping`
- :white_square_button: `profile` (internal command)
- :heavy_check_mark: `serverStatus`
- :heavy_check_mark: `shardConnPoolStats`
- :heavy_check_mark: `top`
- :heavy_check_mark: `validate`
- :white_square_button: `whatsmyuri` (internal command)

#### :white_check_mark: Free monitoring commands 2/2 [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-free-monitoring/) [Anonimongo module](src/anonimongo/dbops/freemonitoring.nim)

- :heavy_check_mark: `getFreeMonitoringStatus`
- :heavy_check_mark: `setFreeMonitoring`

#### :x: <del>Auditing commands 0/1</del>, only available for Mongodb Enterprise and AtlasDB [Mongo doc](https://docs.mongodb.com/manual/reference/command/nav-auditing/) <del>Anonimongo module</del>

- :white_square_button: `logApplicationMessage`



## Caveats
There are several points needed to keep in mind. Those are:

* `diagnostic.explain` and its corresponding `explain`-ed version of various commands haven't
been undergone extensive testing.
* `Query` only provided for `db.find` commands. It's still not supporting Query Plan Cache or
anything regarded that.
* All `readPreference` options are supported except `nearest`.
* Some third-party library which targeting OpenSSL <= 1.0 results in unstable behaviour. See
[issue #7 comment](https://github.com/mashingan/anonimongo/issues/7#issuecomment-674516511)
* All internal connection implementations are Asynchronous IO. No support for multi-threading.
* `retryableWrites` is doing operation twice in case the first attempt is failed. The mongo
reference of it can be found [here][retry-wr]. It's hard to test intentionally fail hence
it hasn't been undergone extensive testing. As it's almost no different with normal operation,
user can retry by themselves to increase of the retrying. Bulk write is reusing the previous
mentioned operations so it's supported too.


[TOC](#table-of-content)
## License
MIT

[1]: https://www.mongodb.com
[2]: https://docs.mongodb.com/manual/reference/command/
[3]: https://github.com/mongodb/specifications
[4]: https://docs.mongodb.com/manual/reference
[5]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo.html
[6]: https://mashingan.github.io/anonimongo/src/htmldocs/theindex.html
[7]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/core/types.html#Database
[8]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/core/types.html#Collection
[9]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/collections.html
[10]: https://github.com/mashingan/anonimongo/tree/master/src/anonimongo/dbops
[wr-doc]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/core/types.html#WriteResult
[retry-wr]: https://docs.mongodb.com/manual/core/retryable-writes/#retryable-writes