# todolist

This example is taken from [Prologue's Example: Todolist](https://github.com/planety/prologue/tree/devel/examples/todolist)
with changes from sqlite to mongodb as database.

This is provided with `docker-compose.yml` and its own `Dockerfile` to make it reproducible build
on any machine that support Docker.

# Run example

In case of just running the example to see how it works, simply run

```
docker-compose up -d
```

and it will download all necessary dependencies.

This docker-compose is also provided `mongo-express` in it so head over
[`http://localhost:8081`](http://localhost:8081)
to access mongodb web client.

In case of tweaking the apps, there will be a need to re-build the image several times hence
it's advisable to run `nimble build` first to populate nimbledeps package to avoid repeated
download each time the image is built.

To rebuild, run command

```
docker-compose up -d --build
```

and this will rebuild the image.

There's often the case where our app failed running, it's because mongodb needs some several seconds
delay first before it can listen the connection. If we're in this situation, run the command

```
docker-compose up -d
```

to restart its running.

Head over [http://localhost:8080](http://localhost:8080) to see the todolist app.