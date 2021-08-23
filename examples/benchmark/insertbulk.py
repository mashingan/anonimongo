import datetime as dt
from datetime import time
import pymongo as pym
#from bson import objectid

client = pym.MongoClient("mongodb://localhost:27017")
db = client["newtemptest"]
coll = db["temptest"]
docs = []
maxiter = 10000
isekai = "hello異世界"
currtime = dt.datetime.now()
curroid = objectid.ObjectId()
coll.drop()
for i in range(maxiter):
    docs.append({
      "hello": i,
      "hello world": isekai,
      "a percent of truth": 0.42,
      "array world": ["red", 50, 4.2],
      "this is null": None,
      "now": currtime,
      #"_id": curroid
        })

def pyinsert():
    coll.insert_many(docs)
    coll.drop()

if __name__ == "__main__":
    import timeit
    setup = "from __main__ import pyinsert"
    numrun = 10
    totaltime = timeit.timeit("pyinsert()", setup=setup, number=numrun)
    print("total runtime: {} seconds in {} runs".format(totaltime, numrun))
    print("average time needed is {} seconds".format(totaltime / numrun))
