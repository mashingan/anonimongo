# switch("path", "$projectDir/../../src")
# when not defined(windows):
#   switch("threads", "on")

# patchFile("stdlib", "asyncmacro", "./asyncmacro")
switch("define", "nimblePath=./nimbledeps")
switch("nimcache", "buildcache")
#switch("threadAnalysis", "off")