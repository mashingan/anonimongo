# Various Benchmark

This folder will accumulate many examples of operations with its benchmark.
With time, it will be added several languages together with its Mongodb
library.  

The Mongodb used is local installation whether system/current os installation
or using Docker to run it in order to avoid network cost timing. We are
measuring the lib itself after all, not our network speeds.

For using Docker, we can simply run

```bash
docker run --rm -dp 27017:27017 mongo:{version}
```

with `version` is the Mongodb version, such as `latest` or `4.2`, or others e.g.
`docker run --rm -dp 27017:27017 mongo:4.2`

## Python setup

The Python is using virtual environment (venv) to avoid polluting workspace.  
To setup the venv, do

```bash
python3 -m venv .
./script/activate
pip install pymongo
```

to create a Python environment in this particular folder and installing pymongo
library.


## Nim setup

For Nim examples, it's depended on `benchy` package so install with nimble

```bash
nimble install benchy
```

and then we can simply run it like

```bash
nim r -d:danger testfile.nim
```

we can add various compile options such as `--gc:arc` or `--gc:orc` to see its
difference.

## Golang setup

As long we have the Golang installation ready, to test we do

```bash
go mod tidy
go test -benchmem -bench .
```

and look for third tab, that has `somenum ns/op`, as the timing.

## Result and Contribution

For this particular (benchmark) examples, any contribution is appreciated to give
a nuanced and fair comparison for each language version.  
By no means the values are absolute as each app/program for each user's case is
 different,
but this should give better information and perspective.  

### Run version
```bash
$ nim -v
Nim Compiler Version 1.4.4 [Windows: amd64]
Compiled at 2021-02-23
Copyright (c) 2006-2020 by Andreas Rumpf

$ python -V
Python 3.9.6

$ go version
go version go1.16.4 windows/amd64
```

### Run mode

```bash
$ nim r -d:danger --gc:orc ./{examplename}.nim

$ python ./{examplename}.py

$ go test -bench . -benchmem
```

### Local result
| Test\Language    	| Nim (ms) 	| Python (ms) 	| Golang (ms) 	|
|------------------	|:--------:	|:-----------:	|:-----------:	|
| insert bulk/many 	|  92.040  	|  151.54565  	|  118.215250 	|