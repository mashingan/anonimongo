# Anonimongo - ANOther pure NIM MONGO driver (WIP)
[Mongodb][1] is a document-based key-value database which emphasize in high performance read
and write capabilities together with many strategies for clustering, consistency, and availability.

Anonimongo is a driver for Mongodb developed using pure Nim. As library, it's developed to enable
developers to be able to access and use Mongodb in projects using Nim. Currently the low level APIs is implemented
however the higher level APIs for easier usage is still in heavy development<sup>TM</sup>.

## Example
TBA, for now see tests code examples.

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

<details><summary>:ballot_box_with_check: Query and write operations commands 6/8</summary>

- [x] `delete`
- [x] `find`
- [x] `findAndModify`
- [x] `getMore`
- [x] `insert`
- [x] `update`
- [ ] `getLastError`
- [ ] `resetError`
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
<details><summary>:ballot_box_with_check: Administration commands 13/29</summary>

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

[1]: https://www.mongodb.com
[2]: https://docs.mongodb.com/manual/reference/command/
[3]: https://github.com/mongodb/specifications