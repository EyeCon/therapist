# Package

version       = "0.1.0"
author        = "Max Grender-Jones"
description   = "Type-safe argument/option parsing with minimal magic"
license       = "MIT"
srcDir        = "src"
bin           = @["therapist"]
installExt    = @["nim"]

from os import splitFile

task tests, "Runs the tests":
    exec "nim c -r --hints:off src/therapist"
    exec "nim rst2html README.rst"
    exec "nim doc src/therapist"

task docs, "Builds documentation":
    exec "nim doc src/therapist"

task clean, "Clean up generated binaries, css and html files":
    for fname in listFiles(getCurrentDir()):
        if fname.splitFile.ext in [".css", ".html"]:
            rmFile fname
    rmFile "src/therapist"
    rmFile "therapist"

# Dependencies

requires "nim >= 1.0.0"
requires "shlex >= 0.1.0"