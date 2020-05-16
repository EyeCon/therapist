import ../src/therapist
import strformat
import strutils
import unittest
import times

type
    IsoDateArg = ref object of ValueArg
        defaultVal: DateTime
        value*: DateTime
        values*: seq[DateTime]
        choices: seq[DateTime]

let DEFAULT_DATE = initDateTime(1, mJan, 2000, 0, 0, 0, 0)

proc newIsoDateArg*(variants: seq[string], help: string, defaultVal = DEFAULT_DATE, choices = newSeq[DateTime](), required=false, optional=false, multi=false): IsoDateArg =
    result = new(IsoDateArg)
    initArg(result, variants, help, defaultVal, choices, required, optional, multi)

method render_choices(arg: IsoDateArg): string = 
    arg.choices.join("|")

method parse(arg: IsoDateArg, value: string, variant: string) =
    try:
        let parsed = parse(value, "YYYY-MM-dd")
        arg.check_choices(parsed, variant)
        arg.value = parsed
        arg.values.add(parsed)
    except ValueError:
        raise newException(ParseError, fmt"Expected a date for {variant}, got: {value}")

proc parseDate(value: string): DateTime = parse(value, "YYYY-MM-dd")

defineArg[DateTime](DateArg, newDateArg, "date", parseDate, DEFAULT_DATE)

suite "grape":
    ## Ideas for options shamelessly stolen from ripgrep / ag etc
    setup:
        let spec = (
            pattern: newStringArg(@["<pattern>"], help="Regular expression pattern used for searching"),
            target: newStringArg(@["<file>", "<path>"], help="A file or directory to search"),
            version: newMessageArg(@["-v", "--version"], "0.1.0", help="Prints version"),
            help: newHelpArg(),
            recursive: newCountArg(@["-r", "--recursive"], help="Recurse into subdirectories"),
            context: newIntArg(@["-C", "--context"], default=2, help="Number of lines of context to print"),
            sensitivity: (
                insensitive: newCountArg(@["-i", "--ignore-case"], help="Case insensitive pattern matching"),
                smartcase: newCountArg(@["-S", "--smart-case"], help="Case insensitive pattern matching for lower case patterns, sensitive otherwise"),
                sensitive: newCountArg(@["-s", "--case-sensitive"], help="Case sensitive pattern matching"),
            ),
            modified: newIsoDateArg(@["-m", "--modified"], defaultVal=DEFAULT_DATE, help="Only review files modified since this date"),
            color: newBoolArg(@["-c", "--color", "--colour"], defaultVal=true, help="Whether to colorise output")
        )

    test "Check default values are populated":
        parse(spec, args = "-S Pattern file.txt", command="grape")
        check(spec.context.seen==false)
        check(spec.context.value==2)

    test "Check alternatives can be detected":
        parse(spec, args = "-S Pattern file.txt", command="grape")
        check(spec.sensitivity.insensitive.seen==false)
        check(spec.sensitivity.smartcase.seen==true)
        check(spec.sensitivity.sensitive.seen==false)

    test "Check alternatives only picked once":
        expect(ParseError):
            parse(spec, args="-s -S pattern file.txt", command="grape")

    test "User-defined date type":
        let (success, message) = spec.parseOrMessage(args = "-m 2020-05-01 corona news.txt", command="grape")
        if not success:
            echo message
        check(success)
        check(spec.modified.value == initDateTime(1, mMay, 2020, 0, 0, 0, 0))

    test "Template-defined boolean type":
        let (success, message) = spec.parseOrMessage(args = "-c false corona news.txt", command="grape")
        if not success:
            echo message
        check(success)
        check(spec.color.seen)
        check(spec.color.value == false)
