# Package

version       = "0.1.0"
author        = "Max Grender-Jones"
description   = "Type-safe argument/option parsing with minimal magic"
license       = "MIT"
srcDir        = "src"
bin           = @["therapist"]

task test, "Runs the tests":
    exec "nim c -r src/therapist"
    exec "nim doc src/therapist"

task docs, "Builds documentation":
    exec "nim doc src/therapist"

# Dependencies

requires "nim >= 1.2.0"
requires "shlex >= 0.1.0"