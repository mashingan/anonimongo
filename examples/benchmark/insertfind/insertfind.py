import asyncio
import datetime as dt
from datetime import time
import motor.motor_asyncio as mio

client = mio.AsyncIOMotorClient("mongodb://localhost:27017")
db = client["newtemptest"]
coll = db["temptest"]
isekai = "hello異世界"
currtime = dt.datetime.now()
coll.drop()
insertnum = 100
lasto = None
async def pyinsert():
  ops = insertnum * [None]
  for i in range(insertnum):
    ops[i] = coll.insert_one({
      "oneHundred": i,
      "hello world": isekai,
      "a percent of truth": 0.42,
      "array world": ["red", 50, 4.2],
      "this is null": None,
      "now": currtime,
    }, bypass_document_validation=True)
  await asyncio.gather(*ops)
  global lasto
  lasto = await coll.find_one({ "oneHundred": insertnum-1 }, limit=1)

if __name__ == "__main__":
    import timeit
    numrun = 100
    totaltime = timeit.timeit(
      "asyncio.get_event_loop().run_until_complete(pyinsert())",
      number=numrun, globals=globals())
    print("total runtime: {} seconds in {} runs".format(totaltime, numrun))
    avgtime = totaltime / numrun
    print("average time needed is {} seconds".format(avgtime))
    print("last object: {}".format(lasto))