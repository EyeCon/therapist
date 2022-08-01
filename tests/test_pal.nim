import strutils
import unittest

import ../src/therapist


suite "pal - the friendly SCM":
    let prolog="An SCM that doesn't hate you"
    let epilog="""For more detail on e.g. the init command, run 'pal init --help'"""

    setup:
        let initspec = (
            destination: newStringArg(@["<destination>"], defaultVal=".", optional=true, help="Location for new repository"),
            template_dir: newDirArg("--template", helpVar="template-directory", help="Specify directory from which template will be used"),
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
            pager: newStringArg("--pager", helpvar="TYPE", help="When to paginate", choices= @["always", "auto", "never"], defaultVal="auto"),
            fishArg: newFishCompletionArg("--fish-completion", help="Renders a fish completion script", helpLevel=1),
            fishCommand: newFishCompletionCommandArg("fish", help="Renders a fish completion script", helpLevel=1),
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
  auth                Set authentication parameters
  init                Create a new repository
  pull                Pull changes from another repository
  push                Push changes to another repository

Options:
  -h, --help          Show help message
      --pager=<TYPE>  When to paginate [default: auto]

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
  <destination>                        Location for new repository [default: .]

Options:
      --template=<template-directory>  Specify directory from which template
                                       will be used
  -h, --help                           Show help message""".strip()
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

    test "Misspelt commands lead to recommendations":
        let parsed = parseOrMessage(spec, prolog, epilog, "pusj", command="pal")
        check(not spec.push.seen)
        check(not parsed.success)
        check(parsed.message.isSome)
        check(parsed.message.get=="Unexpected command: 'pusj' - did you mean 'push'?")
    
    test("Fish completion"):
        let expected="""
complete -e -c pal
complete -c pal -n "__fish_seen_subcommand_from auth" -s h -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from auth" -l help -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from auth" -s u -d 'Username' -r
complete -c pal -n "__fish_seen_subcommand_from auth" -l user -d 'Username' -r
complete -c pal -n "__fish_seen_subcommand_from auth" -s e -d 'Email address' -r
complete -c pal -n "__fish_seen_subcommand_from auth" -l email -d 'Email address' -r
complete -c pal -n "__fish_seen_subcommand_from init" -l template -d 'Specify directory from which template will be used' -F -r
complete -c pal -n "__fish_seen_subcommand_from init" -s h -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from init" -l help -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from pull" -s h -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from pull" -l help -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from push" -s f -d 'Force push'
complete -c pal -n "__fish_seen_subcommand_from push" -l force -d 'Force push'
complete -c pal -n "__fish_seen_subcommand_from push" -s h -d 'Show help message'
complete -c pal -n "__fish_seen_subcommand_from push" -l help -d 'Show help message'
set -l SUBCOMMAND_LIST auth init pull push
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -a "auth" -d 'Set authentication parameters'
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -a "init" -d 'Create a new repository'
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -a "pull" -d 'Pull changes from another repository'
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -a "push" -d 'Push changes to another repository'
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -s h -d 'Show help message'
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -l help -d 'Show help message'
complete -c pal -n "not __fish_seen_subcommand_from $SUBCOMMAND_LIST" -l pager -d 'When to paginate' -f -r -a 'always auto never'
""".strip()
        let (option_success, option_message, _) = parseCopy(spec, args="--fish-completion", command="pal")
        check(option_success)
        check(option_message.isSome)
        let (cmd_success, cmd_message, _) = parseCopy(spec, args="fish", command="pal")
        check(cmd_success)
        check(cmd_message.isSome)
        check(cmd_message.get==option_message.get)
        check(cmd_message.get == expected)
        # echo cmd_message.get
        