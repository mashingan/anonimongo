import std/oids
import anonimongo/core/bson

type
  Entry* = ref object
    id* {.bsonKey: "_id".}: Oid
    title*: string
    isTodo*: bool