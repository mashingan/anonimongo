import prologue
import prologue/middlewares/utils
import prologue/middlewares/staticfile
import ./urls
import std/[os, strutils]

let
  # env = loadPrologueEnv(".env")
  settings = newSettings(appName = getEnv("appName", "Prologue"),
                debug = parseBool getEnv("debug", "yes"),
                port = Port(parseInt getEnv("port", "8080")),
                secretKey = getEnv("secretKey", "")
    )

var app = newApp(settings = settings)

app.use(staticFileMiddleware(getEnv("staticDir", "/staticdir")))
app.use(debugRequestMiddleware())
app.addRoute(urls.urlPatterns, "")
app.run()
