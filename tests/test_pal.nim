import strutils
import unittest

import ../src/therapist


suite "pal - the friendly SCM":
    let prolog="An SCM that doesn't hate you"
    let epilog="""For more detail on e.g. the init command, run 'pal init --help'"""

    setup:
        let initspec = (
            destination: newStringArg(@["<destination>"], defaultVal=".", optional=true, help="Location for new repository"),
            help: newHelpArg()
        )
        let authspec = (
            help: newHelpArg(),
            user: newStringArg(@["-u", "--user"], required=true, help="Username"),
            email: newStringArg(@["-e", "--email"], help="Email address")
        )
        let pullspec = (
            help: newHelpArg(),
            remote: newStringArg(@["<remote>"], optional=true, help="Remote repository"),
        )
        let spec = (
            help: newHelpArg(),
            auth: newCommandArg(@["auth"], authspec, prolog="Set authentication parameters", help="Set authentication parameters"),
            init: newCommandArg(@["init"], initspec, prolog="Create a new repository", help="Create a new repository"),
            pull: newCommandArg(@["pull"], pullspec, prolog="Pull changes from another repository to this one", help="Pull changes from another repository"),
            push: newCommandArg(
                @["push"],
                (
                    destination: newStringArg(@["<remote>"], help="Location of destination repository"),
                    force: newCountArg(@["-f", "--force"], help="Force push"),
                    help: newHelpArg()
                ),
                prolog="Push changes to another repository",
                help="Push changes to another repository",
            ),
        )
    
    test "Help raises MessageError":
        expect(MessageError):
            parse(spec, prolog, epilog, args="--help", command="pal")
    
    test "Help message format":
        try:
            parse(spec, prolog, epilog, args="--help", command="pal")
        except MessageError:
            let message = getCurrentExceptionMsg()
            let expected = """
An SCM that doesn't hate you

Usage:
  pal auth
  pal init [<destination>]
  pal pull [<remote>]
  pal push <remote>
  pal -h|--help

Commands:
  auth        Set authentication parameters
  init        Create a new repository
  pull        Pull changes from another repository
  push        Push changes to another repository

Options:
  -h, --help  Show help message

For more detail on e.g. the init command, run 'pal init --help'""".strip()
            check(message==expected)

    test "Subcommand help raises MessageError":
        expect(MessageError):
            parse(spec, args="init --help", command="pal")
    
    test "Subcommand help format":
        try:
            parse(spec, args="init --help", command="pal")
        except MessageError:
            let message = getCurrentExceptionMsg()
            let expected = """
Create a new repository

Usage:
  pal init [<destination>]
  pal init -h|--help

Arguments:
  <destination>  Location for new repository [default: .]

Options:
  -h, --help     Show help message""".strip()
            check(message==expected)

    test "Subcommand parsing":
        parse(spec, args="init destination", command="pal")
        check(spec.init.seen)
        check(initspec.destination.seen)
        check(initspec.destination.value=="destination")

    test "If commands exist, they must be used":
        expect(ParseError):
            parse(spec, args="destination", command="pal")

    test "Commands are seen even if they receive no parameters":
        parse(spec, args="pull", command="pal")
        check(spec.pull.seen)

    test "Optional Arguments with defaults":
        parse(spec, args="init", command="pal")
        check(spec.init.seen)
        check(initspec.destination.value==".")

    test "Required options":
        expect(ParseError):
            parse(spec, args="auth", command="pal")