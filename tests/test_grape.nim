import ../src/therapist
import os
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

proc newIsoDateArg*(variants: seq[string], help: string, defaultVal = DEFAULT_DATE, choices = newSeq[DateTime](), helpvar="", group="", required=false, optional=false, multi=false, env=""): IsoDateArg =
    result = new(IsoDateArg)
    initArg(result, variants, help, defaultVal, choices, helpvar, group, required, optional, multi, env)

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
        let current = getEnv("PAGER")
        putEnv("PAGER", "loads")

        let spec = (
            pattern: newStringArg(@["<pattern>"], help="Regular expression pattern to look for"),
            target: newPathArg(@["<file>", "<dir>"], help="File(s) or directory(ies) to search", multi=true),
            recursive: newCountArg(@["-r", "--recursive"], help="Recurse into subdirectories", group="File Options"),
            sensitivity: (
                insensitive: newCountArg(@["-i", "--ignore-case"], help="Case insensitive pattern matching", group="Matching Options"),
                smartcase: newCountArg(@["-S", "--smart-case"], help="Case insensitive pattern matching for lower case patterns, sensitive otherwise", group="Matching Options"),
                sensitive: newCountArg(@["-s", "--case-sensitive"], help="Case sensitive pattern matching", group="Matching Options"),
            ),
            follow: newCountArg(@["--[no]follow"], help="Follow symlinks", group="File Options"),
            context: newIntArg(@["-C", "--context"], defaultVal=2, help="Number of lines of context to print", group="Display Options"),
            pager: newStringArg(@["--pager"], env="PAGER", help="Pager to use to display output", group="Display Options"),
            modified: newIsoDateArg(@["-m", "--modified"], defaultVal=DEFAULT_DATE, help="Only review files modified since this date", group="File Options"),
            color: newBoolArg(@["-c", "--color", "--colour"], defaultVal=true, help="Whether to colorise output", group="Display Options"),
            filename: newCountArg(@["-f/-F", "--with-filename/--no-filename"], help="Print filename match was found in", group="Display Options"),
            version: newMessageArg(@["-v", "--version"], "0.1.0", help="Prints version", group="General Options"),
            help: newHelpArg(group="General Options"),
        )
    
    teardown:
        putEnv("PAGER", current)

    test "Help":
        let (success, message) = parseOrMessage(spec, args = "-h", command="grape")
        check(success)
        let expected = """
Usage:
  grape <pattern> (<file>|<dir>)...
  grape -v|--version
  grape -h|--help

Arguments:
  <pattern>                             Regular expression pattern to look for
  <file>, <dir>                         File(s) or directory(ies) to search

File Options:
  -r, --recursive                       Recurse into subdirectories
  --[no]follow                          Follow symlinks
  -m, --modified=<modified>             Only review files modified since this
                                        date

Matching Options:
  -i, --ignore-case                     Case insensitive pattern matching
  -S, --smart-case                      Case insensitive pattern matching for
                                        lower case patterns, sensitive otherwise
  -s, --case-sensitive                  Case sensitive pattern matching

Display Options:
  -C, --context=<context>               Number of lines of context to print
                                        [default: 2]
  --pager=<pager>                       Pager to use to display output
  -c, --color, --colour=<colour>        Whether to colorise output [default:
                                        true]
  -f/-F, --with-filename/--no-filename  Print filename match was found in

General Options:
  -v, --version                         Prints version
  -h, --help                            Show help message
        """.strip()
        check(message.isSome)
        check(message.get == expected)

    test "Check default values are populated":
        parse(spec, args = "-S Pattern README.rst", command="grape")
        check(spec.context.seen==false)
        check(spec.context.value==2)

    test "Check alternatives can be detected":
        parse(spec, args = "-S Pattern README.rst", command="grape")
        check(spec.sensitivity.insensitive.seen==false)
        check(spec.sensitivity.smartcase.seen==true)
        check(spec.sensitivity.sensitive.seen==false)

    test "Check alternatives only picked once":
        expect(ParseError):
            parse(spec, args="-s -S pattern README.rst", command="grape")

    test "User-defined date type":
        let (success, message) = spec.parseOrMessage(args = "-m 2020-05-01 corona README.rst", command="grape")
        if not success:
            echo message
        check(success)
        check(spec.modified.value == initDateTime(1, mMay, 2020, 0, 0, 0, 0))

    test "Template-defined boolean type":
        let (success, message) = spec.parseOrMessage(args = "-c false corona README.rst", command="grape")
        if not success or message.isSome:
            echo message.get
        check(success and message.isNone)
        check(spec.color.seen)
        check(spec.color.value == false)

    test "Test environment variables can be used for values":
        let (success, message) = spec.parseOrMessage(args = "corona README.rst", command="grape")
        check(success and message.isNone)
        check(spec.pager.value == "loads")
            
    test "Test environment variables are overwritten by values":
        let (success, message) = spec.parseOrMessage(args = "--pager none corona README.rst", command="grape")
        check(success and message.isNone)
        check(spec.pager.value == "none")

    test "Check --[no]option format (count up)":
        let (success, message) = spec.parseOrMessage(args = "--follow corona src", command="grape")
        check(success and message.isNone)
        check(spec.follow.seen)
        check(spec.follow.count == 1)

    test "Check --[no]option format (count down)":
        let (success, message) = spec.parseOrMessage(args = "--nofollow corona src", command="grape")
        check(success and message.isNone)
        check(spec.follow.seen)
        check(spec.follow.count == -1)

    test "Check -y/-n option format (count up)":
        let (success, message) = spec.parseOrMessage(args = "-f corona src", command="grape")
        check(success and message.isNone)
        check(spec.filename.seen)
        check(spec.filename.count == 1)

    test "Check -y/-n option format (count down)":
        let (success, message) = spec.parseOrMessage(args = "-F corona src", command="grape")
        check(success and message.isNone)
        check(spec.filename.seen)
        check(spec.filename.count == -1)
    
    test "Check --yes/--no option format (count up)":
        let (success, message) = spec.parseOrMessage(args = "--with-filename corona src", command="grape")
        check(success and message.isNone)
        check(spec.filename.seen)
        check(spec.filename.count == 1)
    
    test "Check --yes/--no option format (count down)":
        let (success, message) = spec.parseOrMessage(args = "--no-filename corona src", command="grape")
        check(success and message.isNone)
        check(spec.filename.seen)
        check(spec.filename.count == -1)