# Package

version       = "0.2.0"
author        = "Max Grender-Jones"
description   = "Type-safe commandline parsing with minimal magic"
license       = "MIT"
srcDir        = "src"
bin           = @["therapist"]
installExt    = @["nim"]

from os import splitFile, `/`
import strformat

task tests, "Runs the tests":
    selfExec "c --hints:off -r src/therapist"
    selfExec "rst2html --hints:off --outdir:build/docs README.rst"
    selfExec "doc --hints:off --outdir:build/docs src/therapist"
    let builddir = "build" / "tests"
    mkDir builddir
    for fname in listFiles("tests"):
        let fileparts = splitFile(fname)
        if fileparts.name.startsWith("test") and fileparts.ext==".nim":
            selfExec fmt"c --hints:off --outdir:{builddir} -r {fname}"
    selfExec fmt"c --hints:off --outdir:{builddir} utils/test_rst"
    exec fmt"{builddir}/test_rst README.rst"

task docs, "Builds documentation":
    let builddir = "build" / "docs"
    mkDir builddir
    selfExec fmt"doc --hints:off --outdir:{builddir} src/therapist"
    selfExec fmt"rst2html --hints:off --outdir:{builddir} README.rst"

task clean, "Clean up generated binaries, css and html files":
    for fname in listFiles(getCurrentDir()):
        if fname.splitFile.ext in [".css", ".html"]:
            rmFile fname
    rmFile "src/therapist"
    rmFile "therapist"
    rmDir "build"

# Dependencies

requires "nim >= 1.0.0"