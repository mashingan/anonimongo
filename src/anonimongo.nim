import anonimongo/core/[auth, bson, pool, types, utils, wire]
import anonimongo/dbops/[aggregation, admmgmt, client, crud, diagnostic,
       freemonitoring, rolemgmt]
import anonimongo/[collections, gridfs]

export auth, bson, pool, types, utils, wire
export admmgmt, client, crud, rolemgmt, aggregation, diagnostic,
       freemonitoring
export collections, gridfs

## ==========
## Anonimongo
## ==========
##
## Mongodb driver implemented in pure Nim. This library support mainly support
## for Mongo version >= 3.4 although some version fewer than that somehow
## supported.
##
## The library currently is consisted by two main path functionalities.
##
## 1. Low level Mongo operations which in turn consisted of two main APIs:
##
##    a. Modules `core` functionalities. (`auth`_, `bson`_, `pool`_, `types`_, `utils`_, `wire`_).
##    b. Modules `dbops` functionalities. (`aggregation`_, `admmgmt`_, `client`_, `crud`_, `diagnostic`_,
##       `freemonitoring`_, `rolemgmt`_).
##
## 2. Higher level which represented as `collections`_ module.
##
## Any casual user would only have to deal with `collections`_ module mainly
## without dabbling into lower level operations. Lower level APIs only used
## when user wants to implement any other commmands operations to add feature
## support.
##
## `collections`_ module has read and write operations in there. Various CRUD APIs
## are implemented and more will be added after some extensive testings.
##
## The `Mongo`_ object has field of `Pool`_ which handle any asynchronous queries
## which default to 64 per `Mongo`_ instance.
##
##
## `bson`_ module is by default accessible from `anonimongo` module lib itself, but
## in case user only wants to use the `BsonDocument`_ itself for data exchange,
## the user would able to access it with ``import anonimongo/core/bson`` to avoid
## importing other `anonimongo` modules. Several examples for its APIs can be found
## in `that page`__ too.
##
## Elaborate examples can be found in `tests<https://github.com/mashingan/anonimongo/tests>`_
## folder in the `Github repo`_ for references on how to do something.
## The specific examples would also be available in `readme.md`_ `examples`_
## from the repo so user can refer that often to check any additional snippet
## example codes.
##
## As usual, all of APIs `index`_ can be found in `that page`__.
##
## .. _auth: anonimongo/core/auth.html
## .. _bson: anonimongo/core/bson.html
## .. _pool: anonimongo/core/pool.html
## .. _types: anonimongo/core/types.html
## .. _utils: anonimongo/core/utils.html
## .. _wire: anonimongo/core/wire.html
## .. _aggregation: anonimongo/dbops/aggregation.html
## .. _admmgmt: anonimongo/dbops/admmgmt.html
## .. _client: anonimongo/dbops/client.html
## .. _crud: anonimongo/dbops/crud.html
## .. _diagnostic: anonimongo/dbops/diagnostic.html
## .. _freemonitoring: anonimongo/dbops/freemonitoring.html
## .. _rolemgmt: anonimongo/dbops/rolemgmt.html
## .. _collections: anonimongo/collections.html
## .. _Mongo: anonimongo/core/types.html#Mongo
## .. _Pool: anonimongo/core/pool.html#Pool
## .. _BsonDocument: anonimongo/core/bson.html#BsonDocument
##
## .. __: bson_
##
## .. _Github repo: https://github.com/mashingan/anonimongo
## .. _readme.md: https://github.com/mashingan/anonimongo/
## .. _examples: https://github.com/mashingan/anonimongo/#examples
## .. _index: https://mashingan.github.io/anonimongo/src/htmldocs/theindex.html
##
## .. __: index_