# See https://github.com/nim-lang/Nim/issues/14352
# In short, this is a hack that extracts code blocks from rst files and runs them as tests
import os
import packages/docutils/rstast
import packages/docutils/rst
import posix_utils
import strformat
import strutils
import terminal
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

proc testFile(filename: string, verbose: bool): int =
    let text = readFile(filename)
    var examples = newSeq[string]()
    # Implementation of the rst parser changed
    when (NimMajor, NimMinor, NimPatch) < (1, 6, 0):
        var hastoc: bool
        let node = rstParse(text, filename, 0, 0, hastoc, {})
        node.gatherExamples(examples)
    elif (NimMajor, NimMinor, NimPatch) < (1, 6, 6):
        let node = rstParse(text, filename, 0, 0, {})
        node.node.gatherExamples(examples)
    else:
        # SandBoxDisabled allows use of include directive
        let node = rstParse(text, filename, 0, 0, {roSandboxDisabled})
        node.node.gatherExamples(examples)
    withTempDir("examples"):
        var master = newSeq[string]()
        for index, example in examples:
            if example.contains(SKIP):
                continue
            let codefile = tempdirname / fmt"{filename.splitFile().name}_example_{index}.nim"
            codefile.writeFile(example)
            if verbose:
                echo example
            master.add(fmt"import {filename.splitFile().name}_example_{index}")
        let master_nim = tempdirname / "master.nim"
        master_nim.writeFile(master.join("\n"))
        result = os.execShellCmd(fmt"nim c -r --hints:off --warnings:off '{master_nim}'")
        if result==0:
            if stdout.isatty:
                styledEcho fgGreen, styleBright, "  [OK] ", resetStyle, fmt"{filename} - {len(examples)} examples"
            else:
                echo fmt"  [OK] {filename} - {len(examples)} examples"
        else:
            if stdout.isatty:
                styledEcho  fgRed, styleBright, "  [Failed] ", resetStyle, fmt"{filename} - {len(examples)} examples"
            else:
                echo fmt"  [Failed] {filename} - {len(examples)} examples"
    


when isMainModule:
    let spec = (
        filename: newFileArg(@["<filename>"], help="RST file to test", multi=true),
        verbose: newCountArg(@["-v", "--verbose"], help="More verbose output"),
        help: newHelpArg()
    )

    spec.parseOrQuit(prolog="Run tests against code examples in an rst file")
    if stdout.isatty:
        styledEcho fgBlue, styleBright, "\n[Doctest]", resetStyle
    else:
        echo "\n[Doctest]"
    for f in spec.filename.values:
        let status = testFile(f, spec.verbose.seen)
        if status!=0:
            quit(status)
