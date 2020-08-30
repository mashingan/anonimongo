# Unittest for anonimongo
Table of contents

* [Administration management command test](#administration-management-command-test)
* [Bson test](#bson-test)
* [Client test](#client-test)
* [Collection methods test](#collection-methods-test)
* [CRUD command test](#crud-command-test)
* [GridFS test](#gridfs-test)
* [Replication set test](#replication-set-test)
* [How to run](#how-to-run)

## Administration management command test
Test file is admmgmt_test.nim. This module tests several APIs defined in [admmgmt][admmgmt.nim] module.
The [admmgmt][admmgmt.nim] mainly tests for administration commands such as [dropDatabase][dropDatabase],
[dropCollection][dropCollection], [listCollections][listCollections], and many more mentioned in the
[documentation][admmgmt_doc].

## Bson test
Test file is bson_test.nim. This extensively tests [Bson module][bson.nim] for several
[BsonDocument][bsondocument] tests together with its use case.

## Client test
Test file is client_test.nim. This extensively tests [client module][client.nim].

## Collection methods test
Test file is collections_test.nim. This tests extensively [Collections][collections.nim] which used widely
for any casual lib user. Common operations implemented here such as [insert][collinsert], [remove][collremove],
[update][collupdate] and [many more][colldoc].

## CRUD command test
Test file is crud_test.nim. This tests CRUD operations in low level defined in [crud.nim][crud.nim] module.
[Collections][collections.nim] offloads many of its CRUD operations to this [module][crud.nim].

## GridFS test
Test file is gridfs_test.nim. This tests [GridFS][gridfs] and [GridStream][gridstream] functionalities.
GridFS commands uploading/downloading and the bucket creation while GridStream acts as file abstraction
above GridFS functions. For full available APIs can be checked [here][grid-doc].

## Replication set test
Test file is test_replication_sslcon.nim. This test any replication operations maintenance starting from
seting it up, connecting through the `mongodb+srv` scheme, emulating fake DNS server for testing the
`mongodb+srv` scheme. The APIs are following the Mongodb Page for [Replication commands](https://docs.mongodb.com/manual/reference/replication/#replication-database-commands) which implemented
in [Replication module](replication.nim).

## How to run
Ideally, this should be added to `nimble test` for running all tests and `nimble test_name` for each
separate test. However since these tests need an elaborate options to ensure it's configurable, the
tests aren't added to `nimble` and need to be run manually. The `nimble test` will eventually be added.  
By default, these tests take the variables defined as compile-arguments constants in file [utils_test.nim](utils_test.nim)
, if the user wants to run in other machine/platform, specify the options on `config.nims` in rootdir project.

For example

```
git clone https://github.com/mashingan/anonimongo
cd anonimongo
cat <<EOF > config.nims
switch("define", "ssl") # if the user wants to connect to SSL/TSL enabled Mongo server
switch("define", "key=/path/to/my/key-file")    # key file for SSL/TLS connection
switch("define", "cert=/path/to/my/cert-file")  # cert file for SSL/TLS connection
switch("define", "nomongod")                    # to disable running new mongod
                                                # process and connect to current
                                                # running mongod process

# defining filename is required when the user wants to run `gridfs_test.nim`
switch("define" "filename=/path/to/big/file/to/upload")
switch("define" "saveas=save_as_other_name_file.mkv_for_example")

# enabling replication set test
switch("define", "testReplication=yes")
EOF

# now running the test
nim c -r tests/test_admmgmt_test.nim
nim c -r tests/test_bson_test.nim
nim c -r tests/test_client_test.nim
nim c -r tests/test_collections_test.nim
nim c -r tests/test_crud_test.nim
nim c -r tests/test_gridfs_test.nim

# or simply
nimble test
```

Any others variable can be checked in that [utils_test.nim](utils_test.nim).  
In the platform where these tests run, the Mongo server only boot-up when the any of test running
(except `test_bson_test.nim`) and then shutdown the Mongo server before the test ends. This only works
when the Mongo server host in `localhost`. Define `nomongod` option (like example above) to disable
booting up Mongo server.

Each test (with exception `test_bson_test.nim`) will create a new Database and its related collections and
immediately drop the database and the collections to avoid polluting the database.  
In case user wants to have a different scenario, for example, inserting several bson documents and leave
it intact without removing it or dropping the collections or database, the user can write his/her own
test scenario.

[admmgmt.nim]: https://github.com/mashingan/anonimongo/blob/develop/src/anonimongo/dbops/admmgmt.nim 
[dropDatabase]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/dbops/admmgmt.html#dropDatabase,Database,BsonBase
[dropCollection]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/dbops/admmgmt.html#dropCollection,Database,string,BsonBase
[listCollections]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/dbops/admmgmt.html#listCollections,Database,string,BsonBase
[admmgmt_doc]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/dbops/admmgmt.html

[bson.nim]: https://github.com/mashingan/anonimongo/blob/develop/src/anonimongo/core/bson.nim
[bsondocument]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/core/bson.html

[client.nim]: https://github.com/mashingan/anonimongo/blob/develop/src/anonimongo/dbops/client.nim

[collections.nim]: https://github.com/mashingan/anonimongo/blob/develop/src/anonimongo/collections.nim
[collinsert]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/collections.html#insert,Collection,seq[BsonDocument],BsonBase
[collremove]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/collections.html#remove,Collection,BsonDocument,bool
[collupdate]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/collections.html#update,Collection,BsonDocument,BsonBase,BsonDocument
[colldoc]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/collections.html

[crud.nim]: https://github.com/mashingan/anonimongo/blob/develop/src/anonimongo/dbops/crud.nim

[gridfs]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/gridfs.html#GridFS
[gridstream]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/gridfs.html#GridStream
[grid-doc]: https://mashingan.github.io/anonimongo/src/htmldocs/anonimongo/gridfs.html

[replication.nim]: https://github.com/mashingan/anonimongo/blob/develop/src/anonimongo/dbops/replication.nim