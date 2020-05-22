import os
import packages/docutils/rstast
import packages/docutils/rst
import posix_utils
import strformat
import strutils
import ../src/therapist

const SKIP = "doctest: skip"

template withTempDir(prefix: string, code: untyped): untyped =
    let tempdirname {.inject.} = absolutePath(mkdtemp(prefix))
    try:
        code
    finally:
        removeDir(tempdirname)

proc gatherExamples(node: PRstNode, examples: var seq[string]) =
    if isnil(node):
        return
    if node.kind == rnCodeBlock:
        let codeBlockSons = node.sons
        if len(codeBlockSons)>0 and codeBlockSons[0].kind == rnDirArg:
            let codeBlockDirArgSons = codeBlockSons[0].sons
            if len(codeBlockDirArgSons)>0 and codeBlockDirArgSons[0].kind == rnLeaf and codeBlockDirArgSons[0].text == "nim":
                for son in codeBlockSons:
                    if son.kind == rnLiteralBlock:
                        examples.add(son.sons[0].text)
    else:
        for son in node.sons:
            gatherExamples(son, examples)

proc testFile(filename: string): int =
    let text = readFile(filename)
    var hastoc: bool
    let node = rstParse(text, filename, 0, 0, hastoc, {})
    var examples = newSeq[string]()
    node.gatherExamples(examples)
    withTempDir("examples"):

        var master = newSeq[string]()
        for index, example in examples:
            if example.contains(SKIP):
                continue
            let codefile = tempdirname / fmt"{filename.splitFile().name}_example_{index}.nim"
            codefile.writeFile(example)
            echo example
            master.add(fmt"import {filename.splitFile().name}_example_{index}")
        let master_nim = tempdirname / "master.nim"
        master_nim.writeFile(master.join("\n"))
        return os.execShellCmd(fmt"nim c -r --hints:off --warnings:off '{master_nim}'")


when isMainModule:
    let spec = (
        filename: newFileArg(@["<filename>"], help="RST file to test", multi=true),
        help: newHelpArg()
    )

    spec.parseOrQuit(prolog="Run tests against code examples in an rst file")
    for f in spec.filename.values:
        let status = testFile(f)
        if status!=0:
            quit(status)
