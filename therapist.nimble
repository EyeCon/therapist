from os import splitFile, `/`
import strformat
import std/algorithm

let buildDir  = "build"

# Package

version       = "2.0.1"
author        = "Max Grender-Jones++"
description   = "Type-safe commandline parsing with minimal magic"
license       = "LGPL"
srcDir        = "src"
bin           = @["therapist"]
binDir        = buildDir / "bin"
installExt    = @["nim"]

# Tasks

task tests, "Runs the tests":
    selfExec "c --hints:off --warning:LockLevel:off -r src/therapist"
    selfExec "rst2html --hints:off --warning:LockLevel:off --outdir:build/docs README.rst"
    selfExec "doc --hints:off --warning:LockLevel:off --outdir:build/docs src/therapist"
    let testDir = buildDir / "tests"
    mkDir testDir
    for fname in sorted(listFiles("tests")):
        let fileparts = splitFile(fname)
        if fileparts.name.startsWith("test") and fileparts.ext==".nim":
            selfExec fmt"c --hints:off --warning:LockLevel:off --outdir:{testDir} -r {fname}"
    selfExec fmt"c --hints:off --warning:LockLevel:off --outdir:{testDir} utils/test_rst"
    exec fmt"{testDir}/test_rst README.rst"

task docs, "Builds documentation":
    let docsDir = buildDir / "docs"
    mkDir docsDir
    selfExec fmt"doc --hints:off --outdir:{docsDir} src/therapist"
    selfExec fmt"rst2html --hints:off --outdir:{docsDir} README.rst"

task clean, "Clean up generated binaries, css and html files":
    for fname in listFiles(getCurrentDir()):
        if fname.splitFile.ext in [".css", ".html"]:
            rmFile fname
    rmFile "src/therapist"
    rmFile "therapist"
    rmDir buildDir

# Dependencies

requires "nim >= 2.0.0"
