# Unittest for anonimongo
Available test are

* [Administration management command test](#administration-management-command-test)
* [Bson test](#bson-test)
* [Client test](#client-test)
* [Collection methods test](#collection-methods-test)
* [CRUD command test](#crud-command-test)
* [GridFS test](#gridfs-test)

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
Test file is gridfs_test.nim. This tests [GridFS](gridfs) and [GridStream](gridstream) functionalities.
GridFS commands uploading/downloading and the bucket creation while GridStream acts as file abstraction
above GridFS functions. For full available APIs can be checked [here](grid-doc).

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