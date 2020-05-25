import options
import strutils
import unittest

import therapist


## Whilst the other tests are intended as illustrations of how you might want to use ``therapist``, the 
## tests in this file are intended to be the simplest possible tests of ``therapist`` functionality for 
## verification purposes

suite "Basic option parsing":
    ## Option Tests:
    ##  - Basic value types can be parsed
    ##  - Incorrect value types throws an error
    ##  - Therapist provides sensible defaults
    ##  - Defaults can be overriden
    ##  - Defaults show up in help messages
    ##  - Help vars can be used to provide clearer help messages
    setup:
        let boring = (
            intval: newIntArg(@["-i", "--int"], help="Some int value"),
            floatval: newFloatArg(@["-f", "--float"], help="Some float value"),
            stringval: newStringArg(@["-s", "--string"], help="Some string value"),
            boolval: newBoolArg(@["-b", "--bool"], help="Some boolean value"),
            help: newHelpArg()
        )
        let boring_defaults = (
            intval: newIntArg(@["-i", "--int"], defaultVal=1, help="Some int value"),
            floatval: newFloatArg(@["-f", "--float"], defaultVal=2.0, help="Some float value"),
            stringval: newStringArg(@["-s", "--string"], defaultVal="s", help="Some string value"),
            boolval: newBoolArg(@["-b", "--bool"], defaultVal=true, help="Some boolean value"),
            help: newHelpArg()
        )
        let boring_helpvars = (
            intval: newIntArg(@["-i", "--int"], help="Some int value", helpvar="I"),
            floatval: newFloatArg(@["-f", "--float"], help="Some float value", helpvar="F"),
            stringval: newStringArg(@["-s", "--string"], help="Some string value", helpvar="S"),
            boolval: newBoolArg(@["-b", "--bool"], help="Some boolean value", helpvar="B"),
            help: newHelpArg()
        )
    
    test "Successful short-option parsing":
        let parsed = boring.parseCopy(args="-i 1 -f 2.0 -s s -b true", command="boring")
        check(parsed.success)
        check(parsed.message.isNone)
        check(parsed.spec.isSome)
        let spec = parsed.spec.get
        check(spec.intval.seen)
        check(spec.intval.count==1)
        check(spec.intval.value==1)
        check(spec.floatval.seen)
        check(spec.floatval.count==1)
        check(spec.floatval.value==2.0)
        check(spec.stringval.seen)
        check(spec.stringval.count==1)
        check(spec.stringval.value=="s")
        check(spec.boolval.seen)
        check(spec.boolval.count==1)
        check(spec.boolval.value==true)

    test "Successful long-option parsing":
        let parsed = boring.parseCopy(args="--int 1 --float 2.0 --string s --bool true", command="boring")
        check(parsed.success)
        check(parsed.message.isNone)
        check(parsed.spec.isSome)
        let spec = parsed.spec.get
        check(spec.intval.seen)
        check(spec.intval.count==1)
        check(spec.intval.value==1)
        check(spec.floatval.seen)
        check(spec.floatval.count==1)
        check(spec.floatval.value==2.0)
        check(spec.stringval.seen)
        check(spec.stringval.count==1)
        check(spec.stringval.value=="s")
        check(spec.boolval.seen)
        check(spec.boolval.count==1)
        check(spec.boolval.value==true)

    test "Incorrect types cause parsing to fail":
        for args in ["-i i", "-f f", "-b b"]:
            let parsed = boring.parseCopy(args=args, command="boring")
            check(not parsed.success)
            check(not parsed.spec.isSome)
            check(parsed.message.isSome)            

    test "Check values are set to sensible defaults if no default is provided":
        let parsed = boring.parseCopy(args="", command="boring")
        check(parsed.success)
        check(parsed.message.isNone)
        check(parsed.spec.isSome)
        let spec = parsed.spec.get
        check(not spec.intVal.seen)
        check(spec.intVal.value==0)
        check(not spec.floatVal.seen)
        check(spec.floatVal.value==0)
        check(not spec.stringVal.seen)
        check(spec.stringVal.value=="")
        check(not spec.boolVal.seen)
        check(spec.boolVal.value==false)

    test "Check values are set to defaults if default is provided":
        let parsed = boring_defaults.parseCopy(args="", command="boring")
        check(parsed.success)
        check(parsed.message.isNone)
        check(parsed.spec.isSome)
        let spec = parsed.spec.get
        check(not spec.intVal.seen)
        check(spec.intVal.value==1)
        check(not spec.floatVal.seen)
        check(spec.floatVal.value==2.0)
        check(not spec.stringVal.seen)
        check(spec.stringVal.value=="s")
        check(not spec.boolVal.seen)
        check(spec.boolVal.value==true)

    test "Check help message without defaults":
        let parsed = boring.parseCopy(args="-h", command="boring")
        check(parsed.success)
        check(parsed.message.isSome)
        check(parsed.spec.isNone)
        let message = parsed.message.get
        let expected = """
Usage:
  boring
  boring -h|--help

Options:
  -i, --int=<int>        Some int value
  -f, --float=<float>    Some float value
  -s, --string=<string>  Some string value
  -b, --bool=<bool>      Some boolean value
  -h, --help             Show help message""".strip()
        check(message==expected)

    test "Check help message with defaults":
        let parsed = boring_defaults.parseCopy(args="-h", command="boring")
        check(parsed.success)
        check(parsed.message.isSome)
        check(parsed.spec.isNone)
        let message = parsed.message.get
        let expected = """
Usage:
  boring
  boring -h|--help

Options:
  -i, --int=<int>        Some int value [default: 1]
  -f, --float=<float>    Some float value [default: 2.0]
  -s, --string=<string>  Some string value [default: s]
  -b, --bool=<bool>      Some boolean value [default: true]
  -h, --help             Show help message""".strip()
        check(message==expected)

    test "Check help message with helpvars":
        let parsed = boring_helpvars.parseCopy(args="-h", command="boring")
        check(parsed.success)
        check(parsed.message.isSome)
        check(parsed.spec.isNone)
        let message = parsed.message.get
        let expected = """
Usage:
  boring
  boring -h|--help

Options:
  -i, --int=<I>     Some int value
  -f, --float=<F>   Some float value
  -s, --string=<S>  Some string value
  -b, --bool=<B>    Some boolean value
  -h, --help        Show help message""".strip()
        check(message==expected)
