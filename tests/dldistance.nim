import ../src/therapist
import ../src/therapistpkg/dldistance

import strformat

const PROLOG = """
Calculates the damerau levenshtein distance between two strings
"""

if isMainModule:
    let spec = (
        a: newStringArg("<a>", help="The first string"),
        b: newStringArg("<b>", help="The second string"),
        sensitive: newCountArg("-s, --sensitive", help="Case sensitive"),
        help: newHelpArg()
    )
    spec.parseOrQuit(prolog=PROLOG)

    echo fmt"{spec.a.value}->{spec.b.value} = {damerau_levenshtein_distance(spec.a.value, spec.b.value, not spec.sensitive.seen)}"