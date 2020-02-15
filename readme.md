# Anonimongo - ANOther pure NIM MONGO driver (WIP)
[Mongodb][1] is a document-based key-value database which emphasize in high performance read
and write capabilities together with many strategies for clustering, consistency, and availability.

Anonimongo is a driver for Mongodb developed using pure Nim. As library, it's developed to enable
developers to be able to access and use Mongodb in projects using Nim. Currently the low level APIs is implemented
however the higher level APIs for easier usage is still in heavy development<sup>TM</sup>.

The APIs are closely following [Mongo documentation][4] with a bit variant for `explain` API. Each supported
command for `explain` added optional string value to indicate the verbosity of `explain` command.  
By default, it's empty string which also indicate the command operations working without the need to
`explain` the queries. For others detailed caveats can be found [here](#caveats).

[This page][5] (`anonimongo.html`) is the elaborate documentation. It also explains several
modules and the categories for those modules. [The index][6] also available.

## Examples
<details><summary>Simple operations</summary>

```nim
import times, strformat
import anonimongo
import anonimongo/collection

var mongo = newMongo(poolconn = 16) # default is 64
if not waitFor mongo.connect:
  # default is localhost:27017
  quit &"Cannot connect to {mongo.host}.{int mongo.port}"
var coll = mongo["temptest"]["colltest"]
var idoc = newseq[BsonDocument](10)
for i in 0 .. idoc.high:
  idoc[i] = bson({
    datetime: currtime + initDuration(hours = i),
    insertId: i
  })
let (success, inserted) = waitfor coll.insert(idoc)
if not success:
  echo "Cannot insert to collection: ", coll.name
else:
  echo "inserted documents: ", inserted

let id5doc = waitfor coll.findOne(bson({
  insertId: 5
}))
doAssert id5doc["datetime"].get == currtime + initDuration(hours = 5)

let oldid8doc = waitfor coll.findAndModify(
  bson({ insertId: 8},
  bson({ "$set": { insertId: 80 }}))
)
let newid8doc = waitfor coll.findOne(bson({ insertId: 80}))
doAssert oldid8doc["datetime"].get.ofTime == newid8doc["datetime"].get
close mongo
```
</details>
<details><summary>Authenticate</summary>

```nim
import strformat
import nimSHA2
import anonimongo

var mongo = newMongo()
let mhostport = &"{mongo.host}.{$mongo.port.int}"
if waitfor not mongo.connect:
  # default is localhost:27017
  quit &"Cannot connect to {mhostport}"
if not authenticate[SHA256Digest](mongo, username, password):
  quit &"Cannot login to {mhostport}"
close mongo

# Another way to connect and login
mongo = newMongo()
mongo.username = username
mongo.password = password
if waitfor not mongo.connect and not waitfor authenticate[SHA256Digest](mongo):
  quit &"Whether cannot connect or cannot login to {mhostport}"
close mongo
```
</details>
<details><summary>URI connect</summary>

```nim
import strformat, uri
import anonimongo

let uriserver = "mongo://username:password@localhost:27017/"
#let sslkey = "/path/to/ssl/key.pem"
#let sslcert = "/path/to/ssl/cert.pem"
#let urissl = &"{uriserver}?tlsCertificateKeyFile=certificate:{encodeURL sslcert},key:{encodeURL sslkey}"

var mongo = newMongo(parseURI uriserver)
close mongo
```

</details>
<details><summary>Manual/URI SSL connect</summary>

```nim
# need to compile with -d:ssl option to enable ssl
import strformat, uri
import anonimongo

let uriserver = "mongo://username:password@localhost:27017/"
let sslkey = "/path/to/ssl/key.pem"
let sslcert = "/path/to/ssl/cert.pem"
let urissl = &"{uriserver}?tlsCertificateKeyFile=certificate:{encodeURL sslcert},key:{encodeURL sslkey}"

# uri ssl connection
var mongo = newMongo(parseURI urissl)
close mongo

# manual ssl connection
var mongo = newMongo(sslinfo = initSSLInfo(sslkey, sslcert))
close mongo
```

</details>

Check [tests](tests/) for more examples of detailed usages.


## Install

```
nimble install https://github.com/mashingan/anonimongo
```

### For dependency

```
requires "https://github.com/mashingan/anonimongo#head"
```

## Implemented APIs
This implemented APIs for Mongo from [Mongo reference manual][2]
and [mongo spec][3].

<details>
<summary>Features connection</summary>

- [x] URI connect
- [x] Multiquery on URI connect
- [ ] Multihost on URI connect
- [ ] Multihost on simple connect
- [x] SSL/TLS connection
- [x] SCRAM-SHA-1 authentication
- [x] SCRAM-SHA-256 authentication
- [x] `isMaster` connection
- [x] `TailableCursor` connection
- [x] `SlaveOk` operations
- [ ] Compression connection
</details>

<details>
<summary>Features commands</summary>

<details><summary>:white_check_mark: Aggregation commands 4/4</summary>

- [x] `aggregate`
- [x] `count`
- [x] `distinct`
- [x] `mapReduce`
</details>

<details><summary>:white_check_mark: Geospatial command 1/1</summary>

- [x] `geoSearch`
</details>

<details><summary>:white_check_mark: Query and write operations commands 7/7 (<del>8</del>)</summary>

- [x] `delete`
- [x] `find`
- [x] `findAndModify`
- [x] `getMore`
- [x] `insert`
- [x] `update`
- [x] `getLastError`
- [ ] `resetError` (deprecated)
</details>

<details><summary>:x: Query plan cache commands 0/6</summary>

- [ ] `planCacheClear`
- [ ] `planCacheClearFilters`
- [ ] `planCacheListFilters`
- [ ] `planCacheListPlans`
- [ ] `planCacheListQueryShapes`
- [ ] `planCacheSetFilter`
</details>

<details><summary>:ballot_box_with_check: Database operations commands 1/3</summary>

- [x] `authenticate`, implemented as Mongo proc.
- [ ] `getnonce`
- [ ] `logout`
</details>
<details><summary>:white_check_mark: User management commands 7/7</summary>

- [x] `createUser`
- [x] `dropAllUsersFromDatabase`
- [x] `dropUser`
- [x] `grantRolesToUser`
- [x] `revokeRolesFromUser`
- [x] `updateUser`
- [x] `usersInfo`
</details>
<details><summary>:white_check_mark: Role management commands 10/10</summary>

- [x] `createRole`
- [x] `dropRole`
- [x] `dropAllRolesFromDatabase`
- [x] `grantPrivilegesToRole`
- [x] `grantRolesToRole`
- [x] `invalidateUserCache`
- [x] `revokePrivilegesFromRole`
- [x] `rovokeRolesFromRole`
- [x] `rolesInfo`
- [x] `updateRole`
</details>

<details><summary>:x: Replication commands 0/13</summary>

- [ ] `applyOps` (internal command)
- [ ] `isMaster`
- [ ] `replSetAbortPrimaryCatchUp`
- [ ] `replSetFreeze`
- [ ] `replSetGetConfig`
- [ ] `replSetGetStatus`
- [ ] `replSetGetStatus`
- [ ] `replSetInitiate`
- [ ] `replSetMaintenance`
- [ ] `replSetReconfig`
- [ ] `replSetResizeOplog`
- [ ] `replSetStepDown`
- [ ] `replSetSyncFrom`
</details>
<details><summary>:x: Sharding commands 0/27</summary>

- [ ] `addShard`
- [ ] `addShardToZone`
- [ ] `balancerStart`
- [ ] `balancerStop`
- [ ] `checkShardingIndex`
- [ ] `clearJumboFlag`
- [ ] `cleanupOrphaned`
- [ ] `enableSharding`
- [ ] `flushRouterConfig`
- [ ] `getShardMap`
- [ ] `getShardVersion`
- [ ] `isdbgrid`
- [ ] `listShard`
- [ ] `medianKey`
- [ ] `moveChunk`
- [ ] `movePrimary`
- [ ] `mergeChunks`
- [ ] `removeShard`
- [ ] `removeShardFromZone`
- [ ] `setShardVersion`
- [ ] `shardCollection`
- [ ] `shardCollection`
- [ ] `split`
- [ ] `splitChunk`
- [ ] `splitVector`
- [ ] `unsetSharding`
- [ ] `updateZoneKeyRange`
</details>
<details><summary>:x: Session commands 0/8</summary>

- [ ] `abortTransaction`
- [ ] `commitTransaction`
- [ ] `endSessions`
- [ ] `killAllSessions`
- [ ] `killAllSessionByPattern`
- [ ] `killSessions`
- [ ] `refreshSessions`
- [ ] `startSession`
</details>
<details><summary>:ballot_box_with_check: Administration commands 13/28 (<del>29</del>)</summary>

- [ ] `clean` (internal namespace command)
- [ ] `cloneCollection`
- [ ] `cloneCollectionAsCapped`
- [ ] `collMod`
- [ ] `compact`
- [ ] `connPoolSync`
- [ ] `convertToCapped`
- [x] `create`
- [x] `createIndexes`
- [x] `currentOp`
- [x] `drop`
- [x] `dropDatabase`
- [ ] `dropConnections`
- [x] `dropIndexes`
- [ ] `filemd5`
- [ ] `fsync`
- [ ] `fsyncUnlock`
- [ ] `getParameter`
- [x] `killCursors`
- [x] `killOp`
- [x] `listCollections`
- [x] `listDatabases`
- [x] `listIndexes`
- [ ] `logRotate`
- [ ] `reIndex`
- [x] `renameCollection`
- [ ] `setFeatureCompabilityVersion`
- [ ] `setParameter`
- [x] `shutdown`
</details>
<details><summary>:white_check_mark: Diagnostic commands 17/17 (<del>26</del>)</summary>

- [ ] `availableQueryOptions` (internal command)
- [x] `buildInfo`
- [x] `collStats`
- [x] `connPoolStats`
- [x] `connectionStatus`
- [ ] `cursorInfo` (removed, use metrics.cursor from `serverStatus` instead)
- [x] `dataSize`
- [x] `dbHash`
- [x] `dbStats`
- [ ] `diagLogging` (removed, on Mongo 3.6, use mongoreplay instead)
- [ ] `driverOIDTest` (internal command)
- [x] `explain`
- [ ] `features` (internal command)
- [x] `getCmdLineOpts`
- [x] `getLog`
- [x] `hostInfo`
- [ ] `isSelf` (internal command)
- [x] `listCommands`
- [ ] `netstat` (internal command)
- [x] `ping`
- [ ] `profile` (internal command)
- [x] `serverStatus`
- [x] `shardConnPoolStats`
- [x] `top`
- [x] `validate`
- [ ] `whatsmyuri` (internal command)
</details>
<details><summary>:x: Free monitoring commands 0/1</summary>

- [ ] `setFreeMonitoring`
</details>
<details><summary>:x: Auditing commands 0/1</summary>

- [ ] `logApplicationMessage`
</details>
</details>

## Caveats
There are several points the quite questionable and prone to change for later development.

<details><summary>Those are:</summary>

* `BsonDocument` will return `Option[BsonBase]` when accessing its field but `BsonBase`
will immediately return `BsonBase` in case it's embedded Bson.
* `BsonTime` which acquired from decoded Bson bytestream will not equal with `Time` from
times module in stdlib. The different caused by Bson only support milliseconds time precision
while Nim `Time` support to nanoseconds. The automatic conversion would supported by `BsonBase == Time`
but not `Time == BsonBase` due defined automatic conversion.
* `diagnostic.explain` and its corresponding `explain`-ed version of various commands haven't
been undergone extensive testing.
* `Query` only provided for `db.find` commands. It's still not supporting Query Plan Cache or
anything regarded that.
* Cannot provide `readPreference` option because cannot support multihost URI connection.
* Will be added more laters when found out more.
</details>

### License
MIT

[1]: https://www.mongodb.com
[2]: https://docs.mongodb.com/manual/reference/command/
[3]: https://github.com/mongodb/specifications
[4]: https://docs.mongodb.com/manual/reference
[5]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo.html
[6]: https://mashingan.github.io/anonimongo/src/htmldocs/theindex.html