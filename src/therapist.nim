import macros
import os
import options
import pegs
import sets
import sequtils
import sugar
import strformat
import strutils
import tables
import terminal
import std/wordwrap
import uri

import therapistpkg/dldistance

export options.get, options.isSome, options.isNone
export damerau_levenshtein_distance, damerau_levenshtein_distance_ascii, dldistance

## .. include:: ../README.rst

const INDENT_WIDTH = 2
const INDENT = spaces(INDENT_WIDTH)

let COMMA = peg """
    comma <- \s*','\s*
"""

# Allows you to capture the o / option in -o / --option
let OPTION_VARIANT_SHORT_FORMAT = peg"""
        option <- ^ shortOption $
        prefix <- '\-'
        shortOption <- prefix {\w}
    """

# Allows you to capture the o / option in -o / --option
let OPTION_VARIANT_LONG_FORMAT = peg"""
        option <- ^ (longOption) $
        prefix <- '\-'
        longOption <- prefix prefix {\w (\w / prefix)+}
    """

# Captures --[no]option and --[no-]option 
let OPTION_VARIANT_NO_FORMAT = peg"""
        option <- ^ longOption $
        prefix <- '\-'
        no <- '\[' {'no' '-'?} '\]'
        longOption <- prefix prefix no {\w (\w / prefix)+}
    """
# Captures --yes / --no
let OPTION_VARIANT_LONG_ALT_FORMAT = peg"""
        option <- ^ (longOption \s* '/' \s* longOption) $
        prefix <- '\-'
        longOption <- prefix prefix {\w (\w / prefix)+}
    """

# Captures -y / -n
let OPTION_VARIANT_SHORT_ALT_FORMAT = peg"""
        option <- ^ (shortOption \s* '/' \s* shortOption) $
        prefix <- '\-'
        shortOption <- prefix {\w}
    """

# Allows you to capture the -o / --option & value in -o=value / --option=value
let OPTION_VALUE_FORMAT = peg"""
        option <- ^ {(shortOption / longOption)} equals {value}
        prefix <- '\-'
        shortOption <- prefix \w
        longOption <- prefix prefix \w (\w / prefix)*
        equals <- '=' / ':'
        value <- _+
    """

let ARGUMENT_VARIANT_FORMAT = peg"""
        argument <- ^ left_bracket word right_bracket $
        left_bracket <- '\<'
        right_bracket <- '\>'
        word <- \ident
    """

# Allows you match against and capture the o in -o
let SHORT_OPTION_VARIANT = peg"""
    option <- ^ prefix {shortOption} $
    prefix <- '\-'
    shortOption <- \w
"""

# Allows you match against and capture the option in --option
let LONG_OPTION_VARIANT = peg"""
    option <- ^ prefix prefix {longOption} $
    prefix <- '\-'
    longOption <- \w (\w / prefix)+
"""


type
    ArgKind = enum
        akPositional,
        akOptional,
        akCommand

    HelpStyle* = enum
        hsColumns, ## Variants and help text shown on the same line
        hsParagraphs ## Variants and help text shown on different lines

    Arg* = ref object of RootObj
        ## Base class for arguments
        variants: seq[string]
        help: string ## The help string for the argument
        longHelp: string ## Longer version of help for the argument
        count*: int ## How many times the argument was seen
        required: bool ## Set to true to make an option required
        optional: bool ## Set to true to make a positional argument optional
        multi: bool ## Set to true to allow the argument to appear more than once
        env: string ## The name of an environment variable to use as a default value
        helpVar: string ## The name of a variable to use as an example name in help messages
        group: string ## The group of help messages the argument should appear in
        helpLevel: Natural ## The help level that governs when the argument is shown
        kind: ArgKind
    ValueArg* = ref object of Arg
        ## Base class for arguments that take a value
        discard
    StringArg* = ref object of ValueArg
        ## An argument or option whose value is a string
        defaultVal: string
        value*: string
        values*: seq[string]
        choices: seq[string]
    FloatArg* = ref object of ValueArg
        ## An argument or option whose value is a float
        defaultVal: float
        value*: float
        values*: seq[float]
        choices: seq[float]
    IntArg* = ref object of ValueArg
        ## An argument or option whose value is an int
        defaultVal: int
        value*: int
        values*: seq[int]
        choices: seq[int]
    PromptArg* = ref object of Arg
        ## Base class for arguments whose value is read from a prompt not an argument
        prompt: string
        secret: bool
    StringPromptArg* = ref object of PromptArg
        defaultVal: string
        value*: string
        values*: seq[string]
        choices: seq[string]
    CountArg* = ref object of Arg
        ## Counts the number of times this argument appears
        defaultVal: int
        choices: seq[int]
        down: HashSet[string]
    HelpArg* = ref object of CountArg
        ## If this argument is provided, a `MessageError` containing a help message will be raised
        showLevel: Natural
        helpStyle: HelpStyle
    MessageArg* = ref object of CountArg
        ## If this argument is provided, a `MessageError` containing a message will be raised
        message: string
    FishCompletionArg = ref object of HelpArg
        ## If this argument is provided, a `MessageError` containing a fish shell completion script will be raised
        discard
    CommandArg* = ref object of Arg
        ## ``CommandArg`` represents a subcommand, which will be processed with its own parser
        specification*: Specification
        handler: proc ()
    HelpCommandArg* = ref object of CommandArg
        ## ``HelpCommandArg`` allows you to create a command that prints help
        showLevel: Natural
        helpStyle: HelpStyle
    MessageCommandArg* = ref object of CommandArg
        ## ``MessageCommandArg`` allows you to create a command that prints a message
        message: string
    FishCompletionCommandArg = ref object of HelpCommandArg
        ## `FishCompletionCommandarg` allows you to create a command that prints a fish shell completion script
        discard
    Alternatives = ref object of RootObj
        seen: bool
        value: Arg

    Specification = ref object
        prolog: string
        epilog: string
        options: OrderedTableRef[string, Arg]
        arguments: OrderedTableRef[string, Arg]
        alternatives: OrderedTableRef[string, Alternatives]
        optionList: seq[Arg]
        argumentList: seq[Arg]
        commandList: seq[CommandArg]
        groups: OrderedTableRef[string, seq[Arg]]

    ArgError* = object of CatchableError
        ## Base Exception for module
        discard

    MessageError* = object of ArgError
        ## Indicates parsing ended early (e.g. because user asked for help). Expected
        ## behaviour is that the exception message will be shown to the user
        ## and the program will terminate indicating success
        discard

    SpecificationError* = object of Defect
        ## Indicates an error in the specification. This error is thrown during an attempt
        ## to create a parser with an invalid specification and as such indicates a
        ## programming error
        discard

    ParseError* = object of ArgError
        ## Indicates parsing ended early (e.g. because user didn't supply correct options).
        ## Expected behaviour is that the exception message will be shown to the user
        ## and the program will terminate indicating failure.
        discard

proc newSpecification(spec: tuple, prolog: string, epilog: string): Specification

proc parse(specification: Specification, args: seq[string], command: string, start=0)

method parse*(arg: Arg, value: string, variant: string) {.base.} =
    ## `parse` is called when a value is seen for an argument. If you
    ## write your own `Arg` you will need to provide a `parse` implementation. If the
    ## value cannot be parsed, a `ParseError` is raised with a user-friendly explanation
    raise newException(Defect, &"Parse not implemented for {$type(arg)}")

proc initArg*[A, T](arg: var A, variants: seq[string], help: string, longHelp: string, defaultVal: T, choices: seq[T], helpVar="", group="", 
                        required: bool, optional: bool, multi: bool, env: string, helpLevel: Natural) =
    ## If you define your own `ValueArg` type, you can call this function to initialise it. It copies the parameter values to the `ValueArg` object
    ## and initialises the `value` field with either the value from the `env` environment key (if supplied and if the key is present in the environment)
    ## or `defaultVal`
    ## 
    ## Since: 0.1.0
    arg.variants = variants
    arg.env = env
    arg.choices = choices
    arg.defaultVal = defaultVal
    arg.help = help
    arg.longHelp = if longHelp!="": longHelp else: help
    arg.group = group
    arg.required = required
    arg.optional = optional
    arg.multi = multi
    arg.helpLevel = helpLevel
    when A is CountArg:
        arg.count = defaultVal
    else:
        if len(env)>0 and existsEnv(env):
            {.hint[ConvFromXtoItselfNotNeeded]:off.}
            # Older versions use tainted string and so need this conversion
            let value = string(getEnv(env))
            {.hint[ConvFromXtoItselfNotNeeded]:on.}
            arg.parse(value, env)
        else:
            arg.value = defaultVal
        arg.values = newSeq[T]()
        arg.helpVar = helpVar
    if required and optional:
        raise newException(SpecificationError, "Arguments can be required or optional not both")

proc initMessageArg*[MA](arg: var MA, variants: seq[string], help: string, longHelp: string, group="", helpLevel: Natural = 0) =
    ## TODO: Rename me
    arg.variants = variants
    arg.help = help
    arg.longHelp = if longHelp!="": longHelp else: help
    arg.group = group
    arg.helpLevel = helpLevel

proc newStringArg*(variants: seq[string], help: string, longHelp = "", defaultVal = "", choices=newSeq[string](), helpvar="", 
                    group="", required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): StringArg =
    ## Creates a new Arg.
    ##
    ## .. code-block:: nim
    ##      :test:
    ##      import options
    ##      import unittest
    ##
    ##      let spec = (
    ##          src: newStringArg(@["<source>"], multi=true, help="Source file(s)"),
    ##          dst: newStringArg(@["<destination>"], help="Destination")
    ##      )
    ##      let (success, message) = parseOrMessage(spec, args="this and_this to_here", command="cp")
    ##      test "Message test":
    ##          check(success and message.isNone)
    ##          check(spec.src.values == @["this", "and_this"])
    ##          check(spec.dst.value == "to_here")
    ##
    ## - `variants` determines how the Arg is presented to the user and whether the arg is a positional
    ##   argument (Argument) or an optional argument (Option)
    ##     - Options take the form `-o` or `--option` (default to `optional` - override with `required=true`)
    ##     - Arguments take the form `<value>` (default to `required` - override wiith `optional=true`)
    ##     - Commands take the form `command`
    ## - `help` is a short form help message to explain what the argument does
    ## - `longHelp` may be used to provide a longer version of the help message to be used with the paragraph help style
    ## - `defaultVal` is a default value
    ## - `choices` is a set of allowed values for the argument
    ## - `helpvar` is a dummy variable name shown to the user in the help message for`ValueArg` (i.e. `--option <helpvar>`).
    ##   Defaults to the longest supplied variant
    ## - `required` implies that an optional argument must appear or parsing will fail
    ## - `optional` implies that a positional argument does not have to appear
    ## - `multi` implies that an Option may appear multiple times or an Argument consume multiple values
    ## - `helpLevel` allows help messages to exclude the arg if it is
    ##   low-priority, enabling `--help` and `--extended-help` help messages.
    ##   Lower values indicate a higher priority. A value of `0` means the arg
    ##   will always be shown in help messages.
    ##
    ## Notes:
    ##  - `multi` is greedy -- the first time it is seen it will consume as many arguments as it can, while
    ##    still allowing any remaining arguments to match
    ##  - `required` and `optional` are mutually exclusive, but `required=false` does not imply `optional=true`
    ##    and vice versa.
    ##
    ## Since: 0.1.0
    result = new(StringArg)
    initArg(result, variants, help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

proc newStringArg*(variants: string, help: string, longHelp = "", defaultVal = "", choices=newSeq[string](), helpvar="", 
                    group="", required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): StringArg =
    ## Convenience method where `variants` are provided as a comma-separated string
    ## 
    ## Since: 0.2.0
    newStringArg(variants.split(COMMA), help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

func initPromptArg(promptArg: PromptArg, prompt: string, secret: bool) =
    promptArg.prompt = prompt
    promptArg.secret = secret

proc newStringPromptArg*(variants: seq[string], help: string, longHelp = "", defaultVal = "", choices=newSeq[string](), helpvar="",
                    group="", required=false, optional=false, multi=false, prompt: string, secret: bool, env="", helpLevel: Natural = 0): StringPromptArg =
    ## Experimental: Creates an argument whose value is read from a prompt rather than the commandline (e.g. a password)
    ##  - `prompt` - prompt to display to the user to request input
    ##  - `secret` - whether to display what the user tyeps (set to `false` for passwords)
    ## 
    ## Since: 0.1.0
    result = new(StringPromptArg)
    initArg(result, variants, help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)
    initPromptArg(PromptArg(result), prompt, secret)

proc newFloatArg*(variants: seq[string], help: string, longHelp = "", defaultVal = 0.0, choices=newSeq[float](), helpvar="", 
                    group="", required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): FloatArg =
    ## A `FloatArg` takes a float value
    ##
    ## .. code-block:: nim
    ##      :test:
    ##
    ##      import options
    ##
    ##      let spec = (
    ##          number: newFloatArg(@["-f", "--float"], help="A fraction input")
    ##      )
    ##      let (success, message) = parseOrMessage(spec, args="-f 0.25", command="hello")
    ##      doAssert success and message.isNone
    ##      doAssert spec.number.seen
    ##      doAssert spec.number.value == 0.25
    ## Since: 0.1.0
    result = new(FloatArg)
    initArg(result, variants, help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

proc newFloatArg*(variants: string, help: string, longHelp = "", defaultVal = 0.0, choices=newSeq[float](), helpvar="", group="", 
                    required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): FloatArg =
    ## Convenience method where `variants` are provided as a comma-separated string
    ## 
    ## Since: 0.2.0
    newFloatArg(variants.split(COMMA), help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)


proc newIntArg*(variants: seq[string], help: string, longHelp = "", defaultVal = 0, choices=newSeq[int](), helpvar="", group="", 
                    required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): IntArg =
    ## An `IntArg` takes an integer value
    ##
    ## .. code-block:: nim
    ##      :test:
    ##
    ##      import options
    ##
    ##      let spec = (
    ##          number: newIntArg(@["-n", "--number"], help="An integer input")
    ##      )
    ##      let (success, message) = parseOrMessage(spec, args="-n 10", command="hello")
    ##      doAssert success and message.isNone
    ##      doAssert spec.number.seen
    ##      doAssert spec.number.value == 10
    ## 
    ## Since: 0.1.0
    result = new(IntArg)
    initArg(result, variants, help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

proc newIntArg*(variants: string, help: string, longHelp = "", defaultVal = 0, choices=newSeq[int](), helpvar="", group="", 
                    required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): IntArg =
    ## Convenience method where `variants` are provided as a comma-separated string
    ## 
    ## Since: 0.2.0
    newIntArg(variants.split(COMMA), help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

proc newCountArg*(variants: seq[string], help: string, longHelp = "", defaultVal = 0, choices=newSeq[int](), group="", 
                    required=false, optional=false, multi=true, env="", helpLevel: Natural = 0): CountArg =
    ## A ``CountArg`` counts how many times it has been seen. When using a ``CountArg``, alternate forms of ``variant`` are valid:
    ## - ``--[no]option`` or ``--[no-]option`` imply that ``--option`` counts up and ``--nooption`` or ``--no-option`` count down
    ## - ``-y/-n`` or ``--yes/--no`` imply that ``-y`` or ``--yes`` count up and ``-n`` or ``--no`` count down.
    ## Except in the case when an equal number of count ups and count downs have been seen, ``arg.seen`` should report seen 
    ## whether or not the current count is greater than or less than zero.
    ## 
    ## If you only expect the argument to be used once, you can use ``newFlagArg`` to make this clear, which is 
    ## equivalent to calling ``newCountArg`` with ``multi=false``
    ## 
    ## .. code-block:: nim
    ##      :test:
    ##
    ##      import options
    ##
    ##      let spec = (
    ##          verbosity: newCountArg(@["-v", "--verbosity"], help="Verbosity"),
    ##          assume: newFlagArg("-y/-n, --yes/--no", help="Assume yes (or no) at any prompts"),
    ##          unicode: newFlagArg("--[no-]unicode", help="Check input is valid unicode (or not)")
    ##      )
    ##      let (success, message) = parseOrMessage(spec, args="-v -v -v -n --unicode", command="hello")
    ##      doAssert success and message.isNone
    ##      doAssert spec.verbosity.seen
    ##      doAssert spec.verbosity.count == 3
    ##      doAssert spec.assume.seen
    ##      doAssert spec.assume.count == -1
    ##      doAssert spec.unicode.seen
    ##      doAssert spec.unicode.count == 1
    ## 
    ## Since: 0.1.0
    result = new(CountArg)
    initArg(result, variants, help, longHelp, defaultVal, choices, helpvar="", group, required, optional, multi, env, helpLevel)

proc newCountArg*(variants: string, help: string, longHelp = "", defaultVal = 0, choices=newSeq[int](), group="", 
                    required=false, optional=false, multi=true, env="", helpLevel: Natural = 0): CountArg =
    ## Convenience method where `variants` are provided as a comma-separated string
    ## 
    ## Since: 0.2.0
    newCountArg(variants.split(COMMA), help, longHelp, defaultVal, choices, group, required, optional, multi, env, helpLevel)

proc newFlagArg*(variants: seq[string], help: string, longHelp = "", defaultVal = 0, choices=newSeq[int](), group="", 
                    required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): CountArg =
    ## Alias for ``newCountArg`` where ``multi=false`` i.e. intended to capture if a particular option
    ## is present or not (e.g. the ``-r`` in ``cp -r``).
    ## 
    ## Since: 0.3.0
    newCountArg(variants, help, longHelp = "", defaultVal, choices, group, required, optional, multi, env, helpLevel)

proc newFlagArg*(variants: string, help: string, longHelp = "", defaultVal = 0, choices=newSeq[int](), group="", 
                    required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): CountArg =
    newCountArg(variants, help, longHelp, defaultVal, choices, group, required, optional, multi, env, helpLevel)

proc newHelpArg*(variants= @["-h", "--help"], help="Show help message", longHelp = "", group="", helpLevel, showLevel: Natural = 0, helpStyle = HelpStyle.hsColumns): HelpArg =
    ## If a help arg is seen, a help message will be shown.
    ##
    ## `showLevel` is compared to the `helpLevel` of each arg. If the arg's
    ## `helpLevel` is greater than the `showLevel`, the arg will be hidden from
    ## the help message. The help arg has its own `helpLevel`, so you can hide
    ## help args from help messages with a lower `showLevel`
    ##
    ## Note: args with a `helpLevel` higher than any helpArg's `showLevel` will
    ## never be shown. This may be desirable in some cases.
    ##
    ## .. code-block:: nim
    ##      :test:
    ##      import options
    ##      import strutils
    ##      let spec = (
    ##          name: newStringArg(@["<name>"], help="Someone to greet"),
    ##          times: newIntArg(@["-t", "--times"], help="How many times to greet them", helpvar="n"),
    ##          help: newHelpArg(@["-h", "--help"], help="Show a help message"),
    ##      )
    ##      let prolog = "Greet someone"
    ##      let (success, message) = parseOrMessage(spec, prolog=prolog, args="-h", command="hello")
    ##      doAssert success and message.isSome
    ##      let expected = """
    ##      Greet someone
    ##
    ##      Usage:
    ##        hello <name>
    ##        hello -h|--help
    ##
    ##      Arguments:
    ##        <name>           Someone to greet
    ##
    ##      Options:
    ##        -t, --times=<n>  How many times to greet them
    ##        -h, --help       Show a help message""".strip()
    ##      doAssert message.get == expected
    ## 
    ## Since: 0.1.0
    result = new(HelpArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)
    result.showLevel = showLevel
    result.helpStyle = helpStyle

proc newHelpArg*(variants: string, help="Show help message", longHelp = "", group="", helpLevel, showLevel: Natural = 0, helpStyle = HelpStyle.hsColumns): HelpArg =
    ## Convenience method where `variants` are provided as a comma-separated string
    ## 
    ## Since: 0.2.0
    newHelpArg(variants.split(COMMA), help, longHelp, group, helpLevel, showLevel, helpStyle)

proc newHelpCommandArg*(variants= @["help"], help="Show help message", longHelp = "", group="", helpLevel, showLevel: Natural = 0, helpStyle = HelpStyle.hsColumns): HelpCommandArg =
    ## Equivalent of `newHelpArg` where help is a command not an option i.e. `> hg help` not `> hg --help`
    ##
    ## Since: 0.2.0
    result = new(HelpCommandArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)
    result.specification = newSpecification((help: newHelpArg()), "", "")
    result.showLevel = showLevel
    result.helpStyle = helpStyle

proc newHelpCommandArg*(variants: string, help="Show help message", longHelp = "", group="", helpLevel, showLevel: Natural = 0, helpStyle = HelpStyle.hsColumns): HelpCommandArg =
    newHelpCommandArg(variants.split(COMMA), help, longHelp, group, helpLevel, showLevel, helpStyle)

proc newFishCompletionCommandArg*(variants: seq[string], help: string, longHelp = "", group="", helpLevel=0, showLevel: Natural = 0): FishCompletionCommandArg =
    result = new(FishCompletionCommandArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)
    result.showLevel = showLevel

proc newFishCompletionCommandArg*(variants: string, help: string, longHelp = "", group="", helpLevel=0, showLevel: Natural = 0): FishCompletionCommandArg =
    newFishCompletionCommandArg(variants.split(COMMA), help, longHelp, group, helpLevel, showLevel)

proc newMessageArg*(variants: seq[string], message: string, help: string, longHelp = "", group="", helpLevel: Natural = 0): MessageArg =
    ## If a `MessageArg` is seen, a message will be shown. Might be used to display a version
    ## number (as per example below) or to display a hand-rolled help message.
    ##
    ## .. code-block:: nim
    ##      :test:
    ##      import options
    ##
    ##      let vspec = (
    ##          version: newMessageArg(@["-v", "--version"], "0.1.0", help="Show the version")
    ##      )
    ##      let (success, message) = parseOrMessage(vspec, args="-v", command="hello")
    ##      doAssert success and message.isSome
    ##      doAssert message.get == "0.1.0"
    ## 
    ## Since: 0.1.0
    result = new(MessageArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)
    result.message = message

proc newMessageArg*(variants: string, message: string, help: string, longHelp = "", group="", helpLevel: Natural = 0): MessageArg =
    ## Convenience method where `variants` are provided as a comma-separated string
    ## 
    ## Since: 0.2.0
    newMessageArg(variants.split(COMMA), message, help, longHelp, group, helpLevel)

proc newMessageCommandArg*(variants: seq[string], message: string, help="Show help message", longHelp = "", group="", helpLevel: Natural = 0): MessageCommandArg =
    ## Equivalent of `newMessageArg` where help is a command not an option i.e. `> hg version` not `> hg --version`
    ##
    ## Since: 0.2.0
    result = new(MessageCommandArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)
    result.specification = newSpecification((help: newHelpArg()), "", "")
    result.message = message

proc newMessageCommandArg*(variants: seq, message: string, help="Show help message", longHelp = "", group="", helpLevel: Natural = 0): MessageCommandArg =
    newMessageCommandArg(variants.split(COMMA), message, help, group, helpLevel)

proc newFishCompletionArg*(variants: seq, help="Show a completion script for fish shell", longHelp = "", group="", helpLevel: Natural = 0): FishCompletionArg =
    result = new(FishCompletionArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)

proc newFishCompletionArg*(variants: string, help="Show a completion script for fish shell", longHelp = "", group="", helpLevel: Natural = 0): FishCompletionArg =
    newFishCompletionArg(variants.split(COMMA), help, longHelp, group, helpLevel)

proc newCommandArg*[S](variants: seq[string], specification: S, help="", longHelp = "", prolog="", epilog="", group="", 
                        helpLevel: Natural = 0, handle: proc(spec: S) = nil): CommandArg =
    ## Version of `newCommandArg` to be used when there is no need to capture options from the main parser
    result = new(CommandArg)
    result.initMessageArg(variants, help, longHelp, group, helpLevel)
    result.specification = newSpecification(specification, prolog, epilog)
    if not isnil(handle):
        result.handler = () => handle(specification)

proc newCommandArg*[S](variants: string, specification: S, help="", longHelp = "", prolog="", epilog="", group="", 
                        helpLevel: Natural = 0, handle: proc(spec: S) = nil): CommandArg =
    ## Convenience version of `newCommandArg` where variants are provided as a string
    newCommandArg(variants.split(COMMA), specification, help, longHelp, prolog, epilog, group, helpLevel, handle)

proc newCommandArg*[S, O](variants: seq[string], specification: S, help="", longHelp = "", prolog="", epilog="", group="", 
                        helpLevel: Natural = 0, handle: proc(spec: S, opts: O), options: O): CommandArg =
    ## A `CommandArg` represents a command which will then use its own parser to parse the remainder
    ## of the arguments. This is how you would implement a multi-command tool like mercurial or git.
    ##
    ## - `variants`: how to invoke the command
    ## - `specification`: the specification of the parser for the command
    ## - `help`: the short help string for the command
    ## - `prolog`: the prolog to be used in the generated help message for the command
    ## - `epilog`: the epilog to be used in the generated help message for the command
    ## - `group`: how to group the command in the main help message
    ## - `helpLevel`: set to a number greater than 0 to have the command only shown in the autogenerated
    ##   help when invoked by a `HelpArg` or `HelpCommandArg` with `helpLevel` set (i.e. verbose help)
    ## - `handle`: a function that can handle a parsed spec of the command
    ## - `options`: any options that you want to make available to the command from the main specification
    ##
    ## For a simple tool, you might choose to use commands the same way as any other argument, all in one file
    ##
    ## .. code-block:: nim
    ##      :test:
    ##      import strutils
    ##      import uri
    ##
    ##      let cloneSpec = (
    ##          url: newURLArg("<url>", help="Repository to clone")
    ##          # ... and the rest...
    ##      )
    ##      let cloneProlog = "Help for the clone command"
    ##      let cloneEpilog = "Example: hg clone https://www.mercurial-scm.org/repo/hg"
    ##      let prolog = "Nim-based reimplementation of mercurial"
    ##      let spec = (
    ##          clone: newCommandArg("clone", cloneSpec, help="Clone a remote repository"),
    ##          help: newHelpCommandArg("help", help="Show help")
    ##          # ... and the rest ...
    ##      )
    ##      var parsed = parseCopy(spec, prolog, command="hg", args="help")
    ##      doAssert parsed.success and parsed.message.isSome
    ##      let expected = """
    ##      Nim-based reimplementation of mercurial
    ##
    ##      Usage:
    ##        hg clone <url>
    ##        hg help
    ##
    ##      Commands:
    ##        clone  Clone a remote repository
    ##        help   Show help""".strip()
    ##      doAssert parsed.message.get == expected
    ##
    ##      let (success, message) = parseOrMessage(spec, prolog, command="hg",
    ##                                 args="clone https://www.mercurial-scm.org/repo/hg")
    ##      doAssert success
    ##      doAssert spec.clone.seen
    ##      # Note how the original cloneSpec has been modified
    ##      doAssert cloneSpec.url.seen
    ##      doAssert cloneSpec.url.value == parseUri("https://www.mercurial-scm.org/repo/hg")
    ##      # Clone the remote repository
    ##
    ## For simple tools, this may be all you need, but there are downsides. In particular, if you want to implement the
    ## `clone` command in a different file then its definition will end up in one file and its implementation in another.
    ## For more complex, multi-file tools, a different pattern is available. Here, `handle` is called to implement the
    ## action implied by the command and `options` is used to pass through options that are defined at the top level
    ##
    ## .. code-block:: nim
    ##      :test:
    ##
    ##      # In common.nim
    ##
    ##      # Options that will be defined at the top level and passed to subsidiary commands.
    ##      # If there are none, then this is not required
    ##      type
    ##          HgOptions* = tuple[
    ##            verbose: CountArg
    ##          ]
    ##
    ##      # In clone.nim -- note how this now contains both the argument definitions
    ##      # and implementation
    ##
    ##      # import common
    ##
    ##      const
    ##          CLONE_PROLOG = "Help for the clone command"
    ##          CLONE_EPILOG = "Example: hg clone https://www.mercurial-scm.org/repo/hg"
    ##
    ##      type
    ##          CloneSpec* = tuple[
    ##              url: URLArg
    ##          ]
    ##
    ##      proc runCloneCommand(spec: CloneSpec, options: HgOptions) =
    ##          doAssert options.verbose.seen
    ##          doAssert spec.url.seen
    ##          # Clone the repository
    ##          discard
    ##
    ##      proc getCloneCommand*(options: HgOptions): CommandArg =
    ##          let spec = (
    ##              url: newURLArg("<url>", help="Repository to clone")
    ##          )
    ##          newCommandArg("clone", spec, prolog=CLONE_PROLOG, epilog=CLONE_EPILOG,
    ##              help="Clone a local or remote repository", handle=runCloneCommand, options=options)
    ##
    ##
    ##      # In hg.nim
    ##
    ##      # import clone
    ##      # import common
    ##
    ##      const
    ##          PROLOG = "Nim-based re-implementation of mercurial"
    ##
    ##      let options: HgOptions = (
    ##          verbose: newCountArg("-v, --verbose", help="More verbose output"),
    ##      )
    ##
    ##      let spec = (
    ##          clone: getCloneCommand(options),
    ##          help: newHelpCommandArg("help", help="Show help"),
    ##          verbose: options.verbose
    ##          # ... and the rest ...
    ##      )
    ##
    ##
    ##      let (success, message) = parseOrMessage(spec, PROLOG, command="hg",
    ##                                  args="-v clone https://www.mercurial-scm.org/repo/hg")
    ##      doAssert success and message.isNone
    ##
    ## The remainder of the implementation is left as an exercise for the reader
    ##
    ## Since:
    ##  - 0.1.0: Initial implementation
    ##  - 0.2.0: `handle` arg and multi-file support
    let handler = (commandSpec: S) => handle(specification, options)
    newCommandArg(variants, specification, help, longHelp, prolog, epilog, group, helpLevel, handler)

proc newCommandArg*[S, O](variants: string, specification: S, help="", longHelp = "", prolog="", epilog="", group="", 
                        helpLevel: Natural = 0, handle: proc(spec: S, opts: O), options: O): CommandArg =
    ## Version of newCommandarg where variants is provided as a string
    newCommandArg(variants.split(COMMA), specification, help, longHelp, prolog, epilog, group, helpLevel, handle, options)

proc newAlternatives(alternatives: tuple): Alternatives =
    result = new(Alternatives)

func addToGroup(specification: Specification, arg: Arg, defaultGroup: string) =
    let group = if len(arg.group)>0: arg.group else: defaultGroup
    if group in specification.groups:
        specification.groups[group].add(arg)
    else:
        specification.groups[group] = @[arg]

proc addArg(specification: Specification, variable: string, arg: Arg) =
    if len(arg.variants)<1:
        raise newException(SpecificationError, "All arguments must have at least one variant: " & variable)
    let first = arg.variants[0]

    if first.startsWith('-'):
        specification.optionList.add(arg)
        specification.addToGroup(arg, "Options")
        arg.kind = akOptional
        var matches: array[2, string]
        var helpVar = ""
        for variant in arg.variants:
            if variant in specification.options:
                raise newException(SpecificationError, fmt"Option {variant} defined twice")
            if variant.match(OPTION_VARIANT_SHORT_FORMAT, matches) or variant.match(OPTION_VARIANT_LONG_FORMAT, matches):
                specification.options[variant] = arg
                if len(matches[0]) > len(helpVar):
                    helpVar = matches[0]
            elif variant.match(OPTION_VARIANT_NO_FORMAT, matches):
                if not (arg of CountArg):
                    raise newException(SpecificationError, fmt "Option {variant} format is only supported for CountArgs")
                let (up, down) = (fmt"--{matches[1]}", fmt"--{matches[0]}{matches[1]}")
                specification.options[up] = arg
                specification.options[down] = arg
                CountArg(arg).down.incl(down)
            elif variant.match(OPTION_VARIANT_LONG_ALT_FORMAT, matches):
                if not (arg of CountArg):
                    raise newException(SpecificationError, fmt"Option {variant} format is only supported for CountArgs")
                let (up, down) = (fmt"--{matches[0]}", fmt"--{matches[1]}")
                specification.options[up] = arg
                specification.options[down] = arg
                CountArg(arg).down.incl(down)
            elif variant.match(OPTION_VARIANT_SHORT_ALT_FORMAT, matches):
                if not (arg of CountArg):
                    raise newException(SpecificationError, fmt "Option {variant} format is only supported for CountArgs")
                let (up, down) = (fmt"-{matches[0]}", fmt"-{matches[1]}")
                specification.options[up] = arg
                specification.options[down] = arg
                CountArg(arg).down.incl(down)
            else:
                raise newException(SpecificationError, fmt"Option {variant} must be in the form -o, --option, --[no]option or --[no-]option")
        if arg of ValueArg:
            # We only want to display a meta var for args that take a value
            if len(arg.helpVar)==0:
                arg.helpVar = fmt"<{helpVar}>"
            elif not (arg.helpVar.startsWith('<') and arg.helpVar.endsWith('>')):
                arg.helpVar = fmt"<{arg.helpVar}>"

    elif first.startsWith('<'):
        if arg of CommandArg:
            raise newException(SpecificationError, fmt"Commands must be declared as 'command', not '<command>' - got '{first}'")
        specification.argumentList.add(arg)
        specification.addToGroup(arg, "Arguments")
        arg.kind = akPositional
        for variant in arg.variants:
            if variant =~ ARGUMENT_VARIANT_FORMAT:
                if variant in specification.arguments:
                    raise newException(SpecificationError, fmt"Argument {variant} already defined")
                specification.arguments[variant] = arg
            else:
                raise newException(SpecificationError, fmt"Argument {variant} must be in the form <argument>")
    else:
        if arg of CommandArg:
            specification.commandList.add(CommandArg(arg))
            specification.addToGroup(arg, "Commands")
            arg.kind = akCommand
            for variant in arg.variants:
                if variant in specification.options:
                    raise newException(SpecificationError, fmt"Command {variant} already defined")
                specification.options[variant] = arg
        else:
            raise newException(SpecificationError, fmt"Arguments must be declared as <argument>, options as -o or --option - got '{first}'")

proc newSpecification(spec: tuple, prolog: string, epilog: string): Specification =
    ## A specification is the specification of a parser. To create it, we need to:
    ## - Create a mapping of variants to options & arguments so we know if we've seen one
    ## - Create a mapping of variants to alternatives so that we know if we've seen an alternative
    ## - Create a list of options & arguments so that we can list them in the help text
    result = new(Specification)
    result.arguments = newOrderedTable[string, Arg]()
    result.options = newOrderedTable[string, Arg]()
    result.alternatives = newOrderedTable[string, Alternatives]()
    result.optionlist = newSeq[Arg]()
    result.argumentList = newSeq[Arg]()
    result.commandList = newSeq[CommandArg]()
    result.groups = newOrderedTable[string, seq[Arg]]()
    result.groups["Commands"] = newSeq[Arg]()
    result.groups["Arguments"] = newSeq[Arg]()
    result.groups["Options"] = newSeq[Arg]()
    result.prolog = prolog
    result.epilog = epilog

    for variable, arg in spec.fieldPairs:
        when arg is Arg:
            result.addArg(variable, arg)
        elif arg is tuple:
            let alternatives = newAlternatives(arg)
            for altvar, altarg in arg.fieldPairs:
                when altarg is Arg:
                    result.addArg(altvar, altarg)
                    for variant in altarg.variants:
                        result.alternatives[variant] = alternatives
                else:
                    {.fatal: "All members of an alternative must be Args".}
        else:
            {.fatal: "All members of the spec tuple must be Args or Alternatives".}

method render_choices(arg: Arg): string {.base.} = ""

method render_choices(arg: StringArg): string =
    arg.choices.join("|")

method render_choices(arg: FloatArg): string =
    arg.choices.join("|")

method render_choices(arg: IntArg): string =
    arg.choices.join("|")

method render_default(arg: Arg): string {.base.} = ""

method render_default(arg: StringArg): string =
    if arg.defaultVal!="": fmt"[default: {arg.defaultVal}]" else: ""

method render_default(arg: FloatArg): string =
    if arg.defaultVal!=0: fmt"[default: {arg.defaultVal}]" else: ""

method render_default(arg: IntArg): string =
    if arg.defaultVal!=0: fmt"[default: {arg.defaultVal}]" else: ""

method render_default(arg: StringPromptArg): string =
    if arg.defaultVal!="": fmt"[default: {arg.defaultVal}]" else: ""

proc order_variants(variants: seq[string]): seq[string] =
    ## Show short variants before long ones
    var short_variants = newSeq[string](0)
    var long_variants = newSeq[string](0)
    for variant in variants:
        if variant =~ OPTION_VARIANT_SHORT_FORMAT or variant =~ OPTION_VARIANT_SHORT_ALT_FORMAT:
            short_variants.add(variant)
        elif variant =~ OPTION_VARIANT_LONG_FORMAT or
                variant =~ OPTION_VARIANT_LONG_ALT_FORMAT or
                variant =~ OPTION_VARIANT_NO_FORMAT:
            long_variants.add(variant)
        else:
            raise newException(ValueError, fmt"""Option format {variant} not handled""")
    short_variants & long_variants


proc render_usage(spec: Specification, command: string, lines: var seq[string], showLevel: Natural) =
    ## Returns an indented list of strings showing usage examples, e.g
    ##   prog command <command_arg>
    ##   prog <arg1> <arg2>
    if len(spec.commandList)>0:
        # If we have a list of commands, use them
        for subcommand in spec.commandList:
            if subcommand.helpLevel > showLevel:
                continue
            let example = command & " " & subcommand.variants.join("|")
            subcommand.specification.render_usage(example, lines, showLevel)
    if len(spec.commandList)==0 or len(spec.argumentList)>0:
        # Otherwise, we create one example, based on the arguments we have
        var example = INDENT & command
        for arg in spec.argumentList:
            if arg.helpLevel > showLevel:
                continue
            let choices = arg.render_choices()
            if len(choices)>0:
                # Arguments that have set values will be rendered as [x|y] or (x|y)
                if arg.optional:
                    example &= fmt" [{choices}]"
                else:
                    example &= fmt" ({choices})"
            else:
                # Arguments that have multilple variants will be rendered as [<x>|<y>] or (<x>|<y>)
                let variants = arg.variants.join("|")
                if arg.optional:
                    example &= fmt" [{variants}]"
                else:
                    if len(arg.variants)>1:
                        example &= fmt" ({variants})"
                    else:
                        example &= fmt" {variants}"
            if arg.multi:
                example &= "..."
        lines.add(example)

proc rewrap(text: string, width=80, newLine="\n"): string =
    var paragraphs = text.split(peg"break <- \n \n+")
    paragraphs.apply((line: string) => wrapWords(line.replace("\n", " "), width, newLine=newLine))
    paragraphs.join(newLine & newLine)

template check_choices*[T](arg: Arg, value: T, variant: string) =
    ## `check_choices` checks that `value` has been set to one of the acceptable `choices` values
    ## 
    ## Since: 0.1.0
    if len(arg.choices)>0 and not (value in arg.choices):
        let message = "Expected " & variant & " value to be " & arg.render_choices() & " , got: '" & $value & "'"
        raise newException(ParseError, message)

method parse(arg: IntArg, value: string, variant: string) =
    try:
        let parsed = parseInt(value)
        arg.check_choices(parsed, variant)
        arg.value = parsed
        arg.values.add(parsed)
    except ValueError:
        raise newException(ParseError, fmt"Expected an integer for {variant}, got: '{value}'")

method parse(arg: FloatArg, value: string, variant: string) =
    try:
        let parsed = parseFloat(value)
        arg.check_choices(parsed, variant)
        arg.value = parsed
        arg.values.add(parsed)
    except ValueError:
        raise newException(ParseError, fmt"Expected a float for {variant}, got: '{value}'")

method parse(arg: StringArg, value: string, variant: string) =
    arg.check_choices(value, variant)
    arg.value = value
    arg.values.add(value)

method parse(arg: StringPromptArg, value: string, variant: string) =
    arg.check_choices(value, variant)
    arg.value = value
    arg.values.add(value)

macro defineArg*[T](TypeName: untyped, cons: untyped, name: string, ArgType: typedesc, parseT: proc (value: string): T, defaultT: T, comment="") =
    ## ``defineArg`` allows you to define your own ``ValueArg`` type simply by providing a ``proc`` that 
    ## can parse a string into a ``T``.
    ## 
    ## - ``T`` The type of the parsed value
    ## - ``TypeName`` The name of your ``ValueArg`` type
    ## - ``cons`` The name of the constructor for your new type
    ## - ``name`` What to call this type in help messages i.e. ``Expected a <name> got ...``
    ## - ``ArgType`` The type of the value (i.e. same as ``T``)
    ## - ``parseT`` A proc that parses a value into a ``T``, raising ``ValueError`` or ``ParseError`` 
    ##   on failure
    ## - ``defaultT`` The default value to use if none is provided (``default(T)`` is often a good bet, 
    ##   but is not defined for all types.)
    ## - ``comment`` The docstring to use in the ``cons`` constructor
    ##
    ## Notes: 
    ## 
    ## - If ``parseT`` fails by raising a ``ValueError`` an error message will be written for you. To
    ##   provide a custom error message, raise a ``ParseError``
    ## - The error messages can get gnarly, parameters in docstring contain `gensym` for unknown reasons
    ##
    ## .. code-block:: nim
    ##    :test:
    ##
    ##    import times
    ##
    ##    # Decide on your default value
    ##    let DEFAULT_DATE = initDateTime(1, mJan, 2000, 0, 0, 0, 0)
    ##
    ##    # Define a parser
    ##    proc parseDate(value: string): DateTime = parse(value, "YYYY-MM-dd")
    ##
    ##    defineArg[DateTime](DateArg, newDateArg, "date", DateTime, parseDate, DEFAULT_DATE)
    ##
    ##    # We can now use newDateArg to define an argument that takes a date
    ##
    ##    let spec = (
    ##      date: newDateArg(@["<date>"], help="Date to change to")
    ##    )
    ##    spec.parse(args="1999-12-31", "set-party-date")
    ##
    ##    doAssert(spec.date.value == initDateTime(31, mDec, 1999, 0, 0, 0, 0))
    ## 
    ## Since: 
    ## - 0.1.0: Initial definition
    ## - 0.3.0: Switch to a macro. ArgType now required, comment now possible
    
    let comment = newCommentStmtNode(comment.strVal)
    result = quote do:
    
        type
            `TypeName`* {.inject.} = ref object of ValueArg
                defaultVal: `ArgType`
                value*: `ArgType`
                values*: seq[`ArgType`]
                choices: seq[`ArgType`]

        proc `cons`*(variants: seq[string], help: string, longHelp = "", defaultVal = `defaultT`, choices = newSeq[`ArgType`](), helpvar="",
                        group="", required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): `TypeName` {.inject.} =
            `comment`
            result = new(`TypeName`)
            result.initArg(variants, help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

        proc `cons`*(variants: string, help: string, longHelp = "", defaultVal= `defaultT`, choices = newSeq[`ArgType`](), helpvar="", group="",
                        required=false, optional=false, multi=false, env="", helpLevel: Natural = 0): `TypeName` {.inject.} =
            `comment`
            `cons`(variants.split(COMMA), help, longHelp, defaultVal, choices, helpvar, group, required, optional, multi, env, helpLevel)

        method render_default(arg: `TypeName`): string =
            if arg.defaultVal!=default(typedesc(`ArgType`)): "[default: " & $arg.defaultVal & "]" else: ""

        method render_choices(arg: `TypeName`): string =
            arg.choices.join("|")

        method parse(arg: `TypeName`, value: string, variant: string) =
            try:
                let parsed = `parseT`(value)
                arg.check_choices(parsed, variant)
                arg.value = parsed
                arg.values.add(parsed)
            except ValueError:
                raise newException(ParseError, "Expected a " & `name` & " for " & variant & ", got: '" & value & "'")

defineArg[bool](BoolArg, newBoolArg, "boolean", bool, parseBool, false, "An argument where the supplied value must be a boolean")

proc parseFile(value: string): string =
    if not fileExists(value):
        raise newException(ParseError, fmt"File '{value}' not found")
    result = value

defineArg[string](FileArg, newFileArg, "file", string, parseFile, "", "An argument where the supplied value must be an existing file")

proc parseDir(value: string): string =
    if not dirExists(value):
        raise newException(ParseError, fmt"Directory '{value}' not found")
    result = value

defineArg[string](DirArg, newDirArg, "directory", string, parseDir, "", "An argument where the supplied value must be an existing directory")

proc parsePath(value: string): string =
    if not (fileExists(value) or dirExists(value)):
        raise newException(ParseError, fmt"Path '{value}' not found")
    result = value

defineArg[string](PathArg, newPathArg, "path", string, parsePath, "", "An argument where the supplied value must be an existing file or directory")

proc parseURL(value: string): Uri =
    let parsed = parseUri(value)
    if not (len(parsed.scheme)>0 and len(parsed.hostname)>0):
        raise newException(ValueError, "Missing scheme / host")
    result = parsed

defineArg[Uri](URLArg, newURLArg, "URL", Uri, parseURL, parseUri(""), "An argument where the supplied value must be a URI")

proc render_help(spec: Specification, command: string, showLevel: Natural = 0, helpStyle = HelpStyle.hsColumns): string =
    var lines = @["Usage:"]
    # Fetch a list of usage examples
    spec.render_usage(command, lines, showLevel)
    # Only include options in usage for the main parser
    for option in spec.optionList:
        if option.helpLevel > showLevel:
            continue
        if option of MessageArg or option of HelpArg:
            let example = INDENT & command & " " & order_variants(option.variants).join("|")
            lines.add(example)
    lines.add("")
    let usage = lines.join("\n")

    let max_width = 80
    var variant_width = 0
    # Find the widest command/argument/option example so we can ensure that the help texts all line up
    for cmd in spec.commandList:
        if cmd.helpLevel > showLevel:
            continue
        variant_width = max(variant_width, len(cmd.variants.join(", ")))
    for argument in spec.argumentList:
        if argument.helpLevel > showLevel:
            continue
        let multi = if argument.multi: "..." else: ""
        variant_width = max(variant_width, len(argument.variants.join(", ") & multi))
    for option in spec.optionList:
        if option.helpLevel > showLevel:
            continue
        let helpVar = if len(option.helpVar)>0: "=" & option.helpVar else: ""
        let multi = if option.multi: "..." else: ""
        variant_width = max(variant_width, len(option.variants.join(", ") & helpVar & multi))

    let help_indent = INDENT_WIDTH + variant_width + INDENT_WIDTH
    let help_width = max_width - help_indent

    let help_para_indent = INDENT_WIDTH * 2
    let help_para_width = max_width - help_para_indent

    lines = newSeq[string]()
    for group, args in spec.groups.pairs:
        if len(args)==0:
            continue
        var argsLines: seq[string]
        for arg in args:
            if arg.helpLevel > showLevel:
                continue
            case helpStyle:
                of HelpStyle.hsColumns:
                    case arg.kind:
                        of akCommand:
                            let help = rewrap(arg.help, help_width).indent(help_indent).strip()
                            argsLines.add(INDENT & alignLeft(arg.variants.join(", "), variant_width) & INDENT & help)
                        of akPositional:
                            let defaultHelp = if arg.optional: " " & arg.render_default() else: ""
                            let help = rewrap(arg.help & defaultHelp, help_width).indent(help_indent).strip()
                            let multi = if arg.multi: "..." else: ""
                            argsLines.add(INDENT & alignLeft(arg.variants.join(", ") & multi, variant_width) & INDENT & help)
                        of akOptional:
                            let defaultHelp = if not arg.required: " " & arg.render_default() else: ""
                            let help = rewrap(arg.help & defaultHelp, help_width).indent(help_indent).strip()
                            let helpVar = if len(arg.helpVar)>0: "=" & arg.helpVar else: ""
                            let multi = if arg.multi: "..." else: ""
                            argsLines.add(INDENT & alignLeft(order_variants(arg.variants).join(", ") & helpVar & multi, variant_width) & INDENT & help)
                of HelpStyle.hsParagraphs:
                    argsLines.add("")
                    case arg.kind:
                        of akCommand:
                            argsLines.add(INDENT & arg.variants.join(", "))
                            argsLines.add(rewrap(arg.longHelp, help_para_width).indent(help_para_indent))
                        of akPositional:
                            let multi = if arg.multi: "..." else: ""
                            argsLines.add(INDENT & arg.variants.join(", ") & multi)
                            argsLines.add(rewrap(arg.longHelp, help_para_width).indent(help_para_indent))
                        of akOptional:
                            let helpVar = if len(arg.helpVar)>0: "=" & arg.helpVar else: ""
                            let multi = if arg.multi: "..." else: ""
                            argsLines.add(INDENT & order_variants(arg.variants).join(", ") & helpVar & multi)
                            argsLines.add(rewrap(arg.longHelp, help_para_width).indent(help_para_indent))

        if argsLines.len > 0:
            # Only include the group if there are some lines in it
            lines.add(&"\n{group}:")
            lines.add(argsLines)

    let prolog = if len(spec.prolog)>0: rewrap(spec.prolog, max_width) & "\n\n" else: spec.prolog
    let epilog = if len(spec.epilog)>0: "\n\n" & rewrap(spec.epilog, max_width) else: spec.epilog
    let args = lines.join("\n")

    result = fmt"{prolog}{usage}{args}{epilog}".strip()

proc render_help*(spec: tuple, prolog="", epilog="", command=extractFilename(getAppFilename()), showLevel: Natural = 0): string =
    ## Renders a help message to be shown for `spec`. Each arg's `helpLevel` is
    ## compared to `showLevel`: if the `helpLevel` is greater, the arg will not
    ## be shown in the help message.
    newSpecification(spec, prolog, epilog).render_help(command, showLevel)

proc render_fish_completion(spec: Specification, command=extractFilename(getAppFilename()), showLevel: Natural): string =
    ### Returns a fish completion script
    proc complete_option(condition: string, variant: string, option: Arg): string =
        let condition = condition.strip()
        let args = if not (option of ValueArg):
            ""
            elif len(option.render_choices())>0:
                fmt""" -f -r -a '{option.render_choices().replace("|", " ")}'"""
            elif (option of PathArg) or (option of DirArg):
                " -F -r"
            else:
                " -r"


        # let require = if option of ValueArg: " -r" else: ""
        # let choices = if len(option.render_choices())>0: " -a " & option.render_choices().replace("|", " ") else: ""
        # option of ValueArg and len(ValueArg(option).choices)>0: "-a " & " ".join(ValueArg(option).choices) else: ""
        var option_text: array[1, string]
        if variant.match(SHORT_OPTION_VARIANT, option_text):
            fmt"""complete -c {command} -n {condition} -s {option_text[0]} -d '{option.help}'{args}"""
        elif variant.match(LONG_OPTION_VARIANT, option_text):
            fmt"""complete -c {command} -n {condition} -l {option_text[0]} -d '{option.help}'{args}"""
        else:
            raise newException(SpecificationError, fmt"Expected a variant in the format -o or --option, got '{variant}'")
    
    var lines = newSeq[string](0)
    lines.add(fmt"complete -e -c {command}")
    var subcommands = newSeq[string](0)
    for subcommand in spec.commandList:
        if subcommand.helpLevel <= showLevel:
            for variant in subcommand.variants:
                subcommands.add(variant)
                for ovariant, option in subcommand.specification.options:
                    if option.helpLevel <= showLevel and option.kind == ArgKind.akOptional:
                        lines.add(complete_option(fmt""""__fish_seen_subcommand_from {variant}" """, ovariant, option))
                            
    let command_list = subcommands.join(" ")
    lines.add(fmt"set -l SUBCOMMAND_LIST {command_list}")
    for subcommand in spec.commandList:
        if subcommand.helpLevel <= showLevel:
            for variant in subcommand.variants:
                lines.add(fmt"""complete -c {command} -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -a "{variant}" -d '{subcommand.help}'""")
    for variant, option in spec.options:
        if option.helpLevel <= showLevel and option.kind == ArgKind.akOptional:
            lines.add(complete_option(fmt""" "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" """, variant, option))                
    lines.join("\n")

method register*(arg: Arg, variant: string, command: string, spec: Specification) {.base.} =
    ## `register` is called by the parser when an argument is seen. If you want to interupt parsing
    ## e.g. to print help, now is the time to do it
    arg.count += 1
    if arg.count>1 and not arg.multi:
        raise newException(ParseError, fmt"Duplicate occurrence of '{variant}'")

method register(arg: MessageArg, variant: string, command: string, spec: Specification) =
    ## This will cause a `MessageError` to be passed back up the chain containing the text from the MessageArg
    procCall Arg(arg).register(variant, command, spec)
    raise newException(MessageError, arg.message)

method register(arg: MessageCommandArg, variant: string, command: string, spec: Specification) =
    ## This will cause a `MessageError` to be passed back up the chain containing the text from the MessageArg
    procCall Arg(arg).register(variant, command, spec)
    raise newException(MessageError, arg.message)

method register(arg: HelpArg, variant: string, command: string, spec: Specification) =
    ## This will cause a `HelpError` to be passed back up the chain, telling the parser to render a help message
    procCall Arg(arg).register(variant, command, spec)
    raise newException(MessageError, spec.render_help(command, arg.showLevel, arg.helpStyle))

method register(arg: HelpCommandArg, variant: string, command: string, spec: Specification) =
    ## This will cause a `HelpError` to be passed back up the chain, telling the parser to render a help message
    procCall Arg(arg).register(variant, command, spec)
    raise newException(MessageError, spec.render_help(command, arg.showLevel, arg.helpStyle))

method register(arg: FishCompletionArg, variant: string, command: string, spec: Specification) =
    ## This will cause a `HelpError` to be passed back up the chain, telling the parser to render a fish completion message
    procCall Arg(arg).register(variant, command, spec)
    raise newException(MessageError, spec.render_fish_completion(command, arg.showLevel))

method register(arg: FishCompletionCommandArg, variant: string, command: string, spec: Specification) =
    ## This will cause a `HelpError` to be passed back up the chain, telling the parser to render a help message
    procCall Arg(arg).register(variant, command, spec)
    raise newException(MessageError, spec.render_fish_completion(command, arg.showLevel))

method register*(arg: CountArg, variant: string, command: string, spec: Specification) =
    if arg.count != 0 and not arg.multi:
        raise newEXception(ParseError, fmt"Duplicate occurence of '{variant}'")
    arg.count += (if variant in arg.down: -1 else: 1)

func seen*(arg: Arg): bool =
    ## `seen` returns `true` if the argument was seen in the input
    ## 
    ## Since: 0.1.0
    arg.count != 0

proc consume(arg: Arg, args: seq[string], variant: string, pos: int, command: string, spec: Specification): int =
    # Consume an argument. ValueArgs consume one argument at a time, Commands consume all the remaining arguments
    arg.register(variant, command, spec)
    if arg of PromptArg:
        let parg = PromptArg(arg)
        let prompt = if len(parg.prompt)>0: parg.prompt else: fmt"{arg.helpvar}: "
        let value = if parg.secret:
            readPasswordFromStdin(prompt)
        else:
            stdout.write(prompt)
            stdout.flushFile()
            stdin.readLine()
        arg.parse(value, variant)
        result = 0
    elif arg of ValueArg:
        if pos < len(args):
            arg.parse(args[pos], variant)
            result = 1
        else:
            raise newException(ParseError, fmt"Missing value for {variant}")
    elif arg of CommandArg:
        parse(CommandArg(arg).specification, args, command=fmt"{command} {variant}", start=pos)
        # Eat 'em all
        result = len(args) - pos
        let handler = CommandArg(arg).handler
        if not isnil(handler):
            handler()

func consume(alternatives: Alternatives, arg: Arg) =
    alternatives.value = arg
    alternatives.seen = true

proc parse(specification: Specification, args: seq[string], command: string, start=0) =
    ## Uses the spec to parse the args. Prolog and epilog are used in the help message; comamnd is the name of the command
    var pos = start
    var positionals = newSeq[string]()

    # First, sift out options - what's left are the positionals
    # Subcommands are contained in the options, as soon as we see a
    # subcommand we will switch to the subcommand parser
    var option_value: array[2, string]
    while pos < len(args):
        # Check for end of options
        if args[pos]=="--":
            pos += 1
            while pos < len(args):
                positionals.add(args[pos])
                pos += 1
        # Check if it's an option (or a command)
        elif args[pos] in specification.options:
            let variant = args[pos]
            let option = specification.options[variant]
            pos += 1
            pos += option.consume(args, variant, pos, command, specification)
            if variant in specification.alternatives:
                let alternatives = specification.alternatives[variant]
                if alternatives.seen:
                    if alternatives.value != option:
                        raise newException(ParseError, fmt"Alternative to {variant} already seen")
                else:
                    alternatives.consume(option)
        # Check if it's an option with a value attached --option=value
        elif args[pos].match(OPTION_VALUE_FORMAT, option_value):
            if option_value[0] notin specification.options:
                raise newException(ParseError, fmt"Unrecognised option: {option_value[0]}")
            let variant = option_value[0]
            let option = specification.options[variant]
            if not (option of ValueArg):
                raise newException(ParseError, fmt"Option {variant} does not take a commandline value")
            pos += 1
            discard option.consume(@[option_value[1]], variant, 0, command, specification)
        # Check if it's an unexpected option
        elif args[pos] =~ OPTION_VARIANT_SHORT_FORMAT or args[pos] =~ OPTION_VARIANT_LONG_FORMAT:
            raise newException(ParseError, fmt"Unrecognised option: {args[pos]}")
        # Check if it's a short option followed by something
        elif args[pos] =~ peg"\-\w.+":
            # Iterate through the letters in the short option
            for index, letter in args[pos].substr(1):
                let variant = "-" & letter
                if variant notin specification.options:
                    raise newException(ParseError, fmt"Unrecognised option: {variant} in {args[pos]}")
                let option = specification.options[variant]
                if option of ValueArg:
                    let value = args[pos].substr(2+index)
                    discard option.consume(@[value], variant, 0, command, specification)
                    break
                else:
                    discard option.consume(@[], variant, 0, command, specification)
            pos += 1
        else:
            if len(specification.argumentList)>0:
                positionals.add(args[pos])
                pos += 1
            elif len(specification.commandList)>0:
                let command = specification.commandList[0]
                let variant = command.variants[0]
                let distance = dlDistance(args[pos], variant)
                var closest = (command: command, variant: variant, distance: distance)
                for command in specification.commandList:
                    for variant in command.variants:
                        let distance = dlDistance(args[pos], variant)
                        if distance <  closest.distance:
                            closest = (command: command, variant: variant, distance: distance)
                if closest.distance==1:
                    raise newException(ParseError, fmt"Unexpected command: '{args[pos]}' - did you mean '{closest.variant}'?")
                raise newException(ParseError, fmt"Unexpected command: {args[pos]}")
            else:
                raise newException(ParseError, fmt"Unexpected argument: {args[pos]}")

    # Check required options have been supplied
    for option in specification.optionList:
        if option.required and not option.seen:
            let variants = option.variants.join(", ")
            raise newException(ParseError, fmt"Missing required option: '{variants}'")

    pos = 0

    # Now process the arguments
    for argpos, argument in specification.argumentList:
        if pos < len(positionals) or not argument.optional:
            pos += argument.consume(positionals, argument.variants[0], pos, command, specification)
            if argument.multi:
                # Multi is greedy
                let num_arguments_remaining = len(specification.argumentList) - (argpos + 1)
                while pos < len(positionals) - num_arguments_remaining:
                    pos += argument.consume(positionals, argument.variants[0], pos, command, specification)
    if pos < len(positionals):
        raise newException(ParseError, fmt"Unconsumed argument: {positionals[pos]}")

proc parse*(specification: tuple, prolog="", epilog="", args: seq[string] = commandLineParams(), command = extractFilename(getAppFilename())) =
    ## Uses the provided specification to parse the input, which defaults to the commandline parameters
    ##
    ## Parameters:
    ## - ``prolog`` - free text that is shown before the autogenerated content in help messages
    ## - ``epilog`` - free text that is shown after the autogenerated content in help messages
    ## - ``args`` - a sequence of arguments to be parsed (defaults to ``commandLineParams()``)
    ## - ``command`` - the name of the program being run (defaults to ``getAppFilename()``)
    ##
    ## Behaviour:
    ##  - If the specification is incorrect (i.e. programmer error), `SpecificationError` is thrown
    ##  - If the parse fails, `ParserError` is thrown
    ##  - If the parse succeeds, but the user should be shown a message a `MessageError` is thrown
    ##  - Otherwise, the parse has suceeded
    ## 
    ## Since: 0.1.0
    parse(newSpecification(specification, prolog, epilog), args, command)

proc parse*(specification: tuple, prolog="", epilog="", args: string, command = extractFilename(getAppFilename())) =
    ## Convenience method where `args` are provided as a space-separated string
    ## 
    ## Since: 0.2.0
    parse(specification, prolog, epilog, parseCmdLine(args), command)

proc parseOrQuit*(spec: tuple, prolog="", epilog="", args: seq[string] = commandLineParams(), command = extractFilename(getAppFilename())) =
    ## Attempts to parse the input. If the parse fails or the user has asked for a message (e.g.
    ## help), show a message and quit. This is probably the ``proc`` you want for a simple commandline script
    ## 
    ## Since: 0.1.0
    try:
        parse(spec, prolog, epilog, args, command)
    except MessageError:
        let message = getCurrentExceptionMsg()
        quit(message, 0)
    except ParseError:
        let message = getCurrentExceptionMsg()
        quit(message, 1)

proc parseOrQuit*(spec: tuple, prolog="", epilog="", args: string, command: string) =
    ## Version of `parseOrQuit` taking `args` as a `string` for convenience
    ## 
    ## Since: 0.1.0
    parseOrQuit(spec, prolog, epilog, parseCmdLine(args), command)

proc parseOrMessage*(spec: tuple, prolog="", epilog="", args: seq[string] = commandLineParams(), command = extractFilename(getAppFilename())): tuple[success: bool, message: Option[string]] =
    ## Version of ``parse`` that returns ``success`` if the parse was sucessful.
    ## If the parse fails, or the result of the parse is an informationl message
    ## for the user, `Option[str]` will containing an appropriate message
    ## 
    ## Since: 0.1.0
    try:
        parse(spec, prolog, epilog, args, command)
        result = (true, none(string))
    except MessageError:
        result = (true, some(getCurrentExceptionMsg()))
    except ParseError:
        result = (false, some(getCurrentExceptionMsg()))

proc parseOrMessage*(spec: tuple, prolog="", epilog="", args: string, command: string): tuple[success: bool, message: Option[string]] =
    ## Version of `parseOrMessage` that accepts `args` as a string for convenience
    ## 
    ## Since: 0.2.0
    result = parseOrMessage(spec, prolog, epilog, parseCmdLine(args), command)

proc parseCopy*[S: tuple](specification: S, prolog="", epilog="", args: seq[string] = commandLineParams(), command = extractFilename(getAppFilename())): tuple[success: bool, message: Option[string], spec: Option[S]] =
    ## Version of ``parse``, similar to ``parseOrMessage`` that returns a copy of the specification
    ## if the parse was successful. Crucially this lets you re-use the original specification, should
    ## you wish. This is probably the ``proc`` you want for writing tests
    ## 
    ## Since: 0.2.0
    let parsed = specification.deepCopy
    let (success, message) = parsed.parseOrMessage(prolog, epilog, args, command)
    result = (success: success, message: message, spec: if success and message.isNone: some(parsed) else: none(S))

proc parseCopy*[S: tuple](specification: S, prolog="", epilog="", args: string, command = extractFilename(getAppFilename())): tuple[success: bool, message: Option[string], spec: Option[S]] =
    ## Version of `parseCopy` that accepts `args` as a string for convenience
    ## 
    ## Since: 0.2.0
    parseCopy(specification, prolog, epilog, parseCmdLine(args), command)

proc parseOrHelp*(spec: tuple, prolog="", epilog="", args: seq[string] = commandLineParams(), command: string = extractFilename(getAppFilename())) =
  ## Attempts to parse the input. If the parse fails, shows the user the error
  ## message and help message, then quits. If the user has asked for a message
  ## (e.g. help), shows the message and quits.
  ## 
  ## Since: 0.2.0
  let helpSpec = spec.deepCopy
  try:
    parse(spec, prolog, epilog, args, command)
  except MessageError as e:
    quit(e.msg, QuitSuccess)
  except ParseError as e:
    let message = helpSpec.renderHelp(e.msg & "\n\n" & prolog, epilog, command)
    quit(message, QuitFailure)

proc parseOrHelp*(spec: tuple, prolog="", epilog="", args: string, command: string = extractFilename(getAppFileName())) =
  ## Convenience version of ``parseOrHelp`` that takes a string for ``args``.
  ## 
  ## Since: 0.2.0
  parseOrHelp(spec, prolog, epilog, parseCmdLine(args), command)

when isMainModule:
    import unittest

    suite "Greeter":
        setup:
            # Example from README.rst
            let spec = (
                # Name is a positional argument, by virtue of being surrounded by < and >
                name: newStringArg(@["<name>"], help="Person to greet"),
                # --times is an optional argument, by virtue of starting with - and/or --
                times: newIntArg(@["-t", "--times"], defaultVal=1, help="How many times to greet"),
                # --version will cause 0.1.0 to be printed
                version: newMessageArg(@["--version"], "0.1.0", help="Prints version"),
                # --help will cause a help message to be printed
                help: newHelpArg(@["-h", "--help"], help="Show help message"),
            )

        test "Hello World":
            parse(spec, args="World", command="hello")
            check(spec.name.value=="World")

        test "Greeter Help":
            try:
                parse(spec, prolog="Greeter", args="-h", command="hello")
            except MessageError:
                let message = getCurrentExceptionMsg()
                let expected = """
Greeter

Usage:
  hello <name>
  hello --version
  hello -h|--help

Arguments:
  <name>               Person to greet

Options:
  -t, --times=<times>  How many times to greet [default: 1]
  --version            Prints version
  -h, --help           Show help message""".strip()
                check(message==expected)


    suite "Strange Copy":
        setup:
            let spec = (
                version: newMessageArg(@["--version"], "0.1.0", help="Prints version. Hopefully will be in semver format, but then does that really make sense for a copy command?"),
                recursive: newCountArg(@["-r", "--recursive"], multi=false, help="Recurse into subdirectories"),
                number: newIntArg(@["-n", "--number"], help="Max number of files to copy", helpvar="n"),
                float: newFloatArg(@["-f", "--float"], help="Max percentage of hard drive", helpvar="pct"),
                verbosity: newCountArg(@["-v", "--verbose"], help="Verbosity (can be repeated)"),
                src: newPathArg(@["<source>"], multi=true, help="Source"),
                dest: newStringArg(@["<destination>"], help="Destination"),
                help: newHelpArg()
            )

        test "Basic parsing":
            parse(spec, args = "-r README.rst to -n=42 --float:0.5 -v -v -v", command="cp")
            check(spec.recursive.seen)
            check(spec.number.seen)
            check(spec.number.value==42)
            check(spec.float.seen)
            check(spec.float.value==0.5)
            check(spec.src.seen)
            check(spec.src.value=="README.rst")
            check(spec.dest.seen)
            check(spec.dest.value=="to")
            check(spec.verbosity.seen)
            check(spec.verbosity.count==3)

        test "Short options can take values without spaces/separators":
            parse(spec, args = "README.rst to -n42")
            check(spec.number.seen)
            check(spec.number.value==42)

        test "Arguments can have multiple values":
            parse(spec, args = @["README.rst", "therapist.nimble", "to_here"], command="cp")
            check(spec.src.seen)
            check(spec.src.values == @["README.rst", "therapist.nimble"])
            check(spec.dest.seen)
            check(spec.dest.value == "to_here")

        test "parseCopy can be reused":
            let parsed = spec.parseCopy(args="README.rst destination.rst", command="cp")
            check(parsed.success)
            check(parsed.message.isNone)
            check(parsed.spec.isSome)
            check(parsed.spec.get.src.seen)
            check(not spec.src.seen)

        test "Unexpected options raise a parse error":
            expect(ParseError):
                parse(spec, args = @["-x"], command="cp")

        test "Help raises message error":
            expect(MessageError):
                parse(spec, args = @["-h"], command="cp")

        test "Help raises message error in a multiletter short option":
            expect(MessageError):
                parse(spec, args = @["-vh"], command="cp")

        test "Unexpected options in multiletter short options raise a parse error":
            expect(ParseError):
                parse(spec, args = @["-vx"], command="cp")

        test "Simple help format":
            try:
                parse(spec, args = @["-h"], command="cp")
            except MessageError:
                let message = getCurrentExceptionMsg()
                let expected = """
Usage:
  cp <source>... <destination>
  cp --version
  cp -h|--help

Arguments:
  <source>...        Source
  <destination>      Destination

Options:
  --version          Prints version. Hopefully will be in semver format, but
                     then does that really make sense for a copy command?
  -r, --recursive    Recurse into subdirectories
  -n, --number=<n>   Max number of files to copy
  -f, --float=<pct>  Max percentage of hard drive
  -v, --verbose...   Verbosity (can be repeated)
  -h, --help         Show help message
""".strip()
                check(message==expected)

        test "Print args raise MessageError":
            expect(MessageError):
                parse(spec, args = @["--version"], command="cp")

        test "Message error content is correct":
            try:
                parse(spec, args = @["--version"], command="cp")
            except MessageError:
                let message = getCurrentExceptionMsg()
                check(message=="0.1.0")

        test "Int parsing error":
            expect(ParseError):
                parse(spec, args = @["-n", "carrot"])

        test "Float parsing error":
            expect(ParseError):
                parse(spec, args = @["-f", "banana"])

        test "Missing argument":
            expect(ParseError):
                parse(spec, args = @["source"])

    suite "Peg test":
        test "Option no format":
            var matches: array[2, string]
            check(match("--[no]colour", OPTION_VARIANT_NO_FORMAT, matches))
            check(matches[0]=="no")
            check(matches[1]=="colour")
            check(match("--[no-]colour", OPTION_VARIANT_NO_FORMAT, matches))
            check(matches[0]=="no-")
            check(matches[1]=="colour")
            check(not ("--colour" =~ OPTION_VARIANT_NO_FORMAT))
            check(not ("--[no]c" =~ OPTION_VARIANT_NO_FORMAT))
            check(not ("--[]colour" =~ OPTION_VARIANT_NO_FORMAT))
            check(not ("--colour" =~ OPTION_VARIANT_NO_FORMAT))
            check(not ("--[some]colour" =~ OPTION_VARIANT_NO_FORMAT))

        test "Long option alt peg format":
            var matches: array[2, string]
            check(match("--black/--white", OPTION_VARIANT_LONG_ALT_FORMAT, matches))
            check(matches[0]=="black")
            check(matches[1]=="white")
            check("--black /--white" =~ OPTION_VARIANT_LONG_ALT_FORMAT)
            check("--black/ --white" =~ OPTION_VARIANT_LONG_ALT_FORMAT)
            check("--black / --white" =~ OPTION_VARIANT_LONG_ALT_FORMAT)
            check(not ("--black" =~ OPTION_VARIANT_LONG_ALT_FORMAT))
            check(not ("--black / --white / --grey" =~ OPTION_VARIANT_LONG_ALT_FORMAT))

        test "Short option alt peg format":
            var matches: array[2, string]
            check(match("-b/-w", OPTION_VARIANT_SHORT_ALT_FORMAT, matches))
            check(matches[0]=="b")
            check(matches[1]=="w")
            check("-b /-w" =~ OPTION_VARIANT_SHORT_ALT_FORMAT)
            check("-b/ -w" =~ OPTION_VARIANT_SHORT_ALT_FORMAT)
            check("-b / -w" =~ OPTION_VARIANT_SHORT_ALT_FORMAT)
            check(not ("-b" =~ OPTION_VARIANT_SHORT_ALT_FORMAT))
            check(not ("-b / -w / -g" =~ OPTION_VARIANT_SHORT_ALT_FORMAT))

        test "Comma split":
            check("-o, --option".split(COMMA) == @["-o", "--option"])

    suite "Hidden args":
        setup:
            let spec = (
                version: newMessageArg(@["--version"], "0.1.0", help="Prints version info",  helpLevel = 2),
                recursive: newFlagArg(@["-r", "--recursive"], help="Recurse into subdirectories"),
                number: newIntArg(@["-n", "--number"], help="Max number of files to copy", helpvar="n", helpLevel = 2),
                float: newFloatArg(@["-f", "--float"], help="Max percentage of hard drive", helpvar="pct", helpLevel = 2),
                verbosity: newCountArg(@["-v", "--verbose"], help="Verbosity (can be repeated)"),
                src: newPathArg(@["<source>"], multi=true, help="Source"),
                dest: newStringArg(@["<destination>"], help="Destination"),
                help: newHelpArg(),
                extHelp: newHelpArg("--extended-help", help = "Show full help message", showLevel = high(Natural))
            )

        test "Hidden args not shown in usage or options":
            try:
                parse(spec, args = @["-h"], command="cp")
            except MessageError:
                let message = getCurrentExceptionMsg()
                let expected = """
Usage:
  cp <source>... <destination>
  cp -h|--help
  cp --extended-help

Arguments:
  <source>...       Source
  <destination>     Destination

Options:
  -r, --recursive   Recurse into subdirectories
  -v, --verbose...  Verbosity (can be repeated)
  -h, --help        Show help message
  --extended-help   Show full help message
""".strip()
                check(message == expected)

        test "Hidden args shown when requested":
          try:
              parse(spec, args = @["--extended-help"], command = "cp")
          except MessageError:
              let message = getCurrentExceptionMsg()
              let expected = """
Usage:
  cp <source>... <destination>
  cp --version
  cp -h|--help
  cp --extended-help

Arguments:
  <source>...        Source
  <destination>      Destination

Options:
  --version          Prints version info
  -r, --recursive    Recurse into subdirectories
  -n, --number=<n>   Max number of files to copy
  -f, --float=<pct>  Max percentage of hard drive
  -v, --verbose...   Verbosity (can be repeated)
  -h, --help         Show help message
  --extended-help    Show full help message
""".strip()
              check(message == expected)