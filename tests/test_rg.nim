import strutils
import unittest

import ../src/therapist

# This is a test for creation of paragraph-style help messages, as featured in ripgrep / fish shell's complete command
# The help messages are taken from ripgrep itself - hopefully this homage is appreciated!
# See: https://github.com/BurntSushi/ripgrep/blob/master/crates/core/app.rs


const
    PROLOG = """
ripgrep 13.0.0
Andrew Gallant <jamslam@gmail.com>

ripgrep (rg) recursively searches the current directory for a regex pattern.
By default, ripgrep will respect gitignore rules and automatically skip hidden
files/directories and binary files.

Use -h for short descriptions and --help for more details.

Project home page: https://github.com/BurntSushi/ripgrep""".strip()

    PATTERN_HELP = """
A regular expression used for searching. To match a pattern beginning with a
dash, use the -e/--regexp flag.

For example, to search for the literal '-foo', you can use this flag:

    rg -e -foo

You can also use the special '--' delimiter to indicate that no more flags
will be provided. Namely, the following is equivalent to the above:

    rg -- -foo
""".strip()

    PATH_HELP = """
A file or directory to search. Directories are searched recursively. File paths
specified on the command line override glob and ignore rules.""".strip()

    AFTER_HELP = """
Show NUM lines after each match.

This overrides the --context and --passthru flags.""".strip()

    COLOR_HELP = """
This flag specifies color settings for use in the output. This flag may be
provided multiple times. Settings are applied iteratively. Colors are limited
to one of eight choices: red, blue, green, cyan, magenta, yellow, white and
black. Styles are limited to nobold, bold, nointense, intense, nounderline
or underline.

The format of the flag is '{type}:{attribute}:{value}'. '{type}' should be
one of path, line, column or match. '{attribute}' can be fg, bg or style.
'{value}' is either a color (for fg and bg) or a text style. A special format,
'{type}:none', will clear all color settings for '{type}'.

For example, the following command will change the match color to magenta and
the background color for line numbers to yellow:

    rg --colors 'match:fg:magenta' --colors 'line:bg:yellow' foo.

Extended colors can be used for '{value}' when the terminal supports ANSI color
sequences. These are specified as either 'x' (256-color) or 'x,x,x' (24-bit
truecolor) where x is a number between 0 and 255 inclusive. x may be given as
a normal decimal number or a hexadecimal number, which is prefixed by `0x`.

For example, the following command will change the match background color to
that represented by the rgb value (0,128,255):

    rg --colors 'match:bg:0,128,255'

or, equivalently,

    rg --colors 'match:bg:0x0,0x80,0xFF'

Note that the the intense and nointense style flags will have no effect when
used alongside these extended color codes.""".strip()

    SHORT_HELP = staticRead("test_rg_short.txt").strip()

    LONG_HELP = staticRead("test_rg_long.txt").strip()


suite "rg: Paragraph-style help":
    setup:
        let spec = (
            pattern: newStringArg("<pattern>", help="A regular expression used for searching.", longHelp=PATTERN_HELP),
            path: newStringArg("<path>", optional=true, help="A file or directory to search.", longHelp=PATH_HELP, multi=true),
            after: newIntArg("-A, --after-context", helpVar="<NUM>", help="Show NUM lines after each match.", longHelp=AFTER_HELP),
            color: newStringArg("--colors", helpVar="COLOR_SPEC", help="Configure color settings and styles.", longHelp=COLOR_HELP, multi=true),
            help: newHelpArg("-h", help="Show a short-form help message", helpLevel=2, helpStyle=HelpStyle.hsColumns),
            longHelp: newHelpArg("--help", help="Show a long-form help message", helpLevel=2, helpStyle=HelpStyle.hsParagraphs)
        )

    test "Short Help":
        let (success, message) = spec.parseOrMessage(prolog=PROLOG, args="-h", command="rg")
        check(success)
        check(message.isSome)
        check(message.get==SHORT_HELP)

    test "Long Help":
        let (success, message) = spec.parseOrMessage(prolog=PROLOG, args="--help", command="rg")
        check(success)
        check(message.isSome)
        let actual = message.get.strip
        if actual!=LONG_HELP:
            # It's ok if the difference is blank lines with leading spaces added at the beginning of help messages
            let received_lines = actual.splitLines()
            let expected_lines = LONG_HELP.splitLines()
            check(len(expected_lines) == len(received_lines))
            for i, line in received_lines.pairs:
                if len(received_lines[i].strip) == 0:
                    check(received_lines[i].strip == expected_lines[i].strip)
                else:
                    check(received_lines[i] == expected_lines[i])
        else:
            check(message.get.strip==LONG_HELP)