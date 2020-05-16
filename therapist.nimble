# Package

version       = "0.1.0"
author        = "Max Grender-Jones"
description   = "Type-safe argument/option parsing with minimal magic"
license       = "MIT"
srcDir        = "src"
bin           = @["therapist"]
installExt    = @["nim"]

from os import splitFile, `/`
import strformat

after clean:
    rmDir "build"

task tests, "Runs the tests":
    selfExec "c --hints:off -r src/therapist"
    selfExec "rst2html --hints:off --outdir:build/docs README.rst"
    selfExec "doc --hints:off --outdir:build/docs src/therapist"
    mkDir "build" / "tests"
    for fname in listFiles("tests"):
        let fileparts = splitFile(fname)
        if fileparts.ext==".nim":
            selfExec fmt"c --hints:off --outdir:build/tests -r {fname}"

task docs, "Builds documentation":
    exec "nim doc --hints:off --outdir: build/docs src/therapist"

task clean, "Clean up generated binaries, css and html files":
    for fname in listFiles(getCurrentDir()):
        if fname.splitFile.ext in [".css", ".html"]:
            rmFile fname
    rmFile "src/therapist"
    rmFile "therapist"

# Dependencies

requires "nim >= 1.0.0"
requires "shlex >= 0.1.0"