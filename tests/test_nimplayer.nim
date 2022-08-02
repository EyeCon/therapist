import ../src/therapist
import strutils
import unittest

suite "Nimplayer":
    setup:
        let playspec = (
            volume: newCountArg(@["-v", "--volume"], help="Volume"),
            start: newIntArg(@["-s", "--start"], help="Start after s seconds"),
            # Note this would naturally be a newFileArg, but then testing would be harder since
            # any files referred to would have to exist
            filename: newStringArg(@["<filename>"], help="Filename to play"),
        )
        let spec = (
            verbose: newCountArg(@["-v", "--verbose"], help="Verbosity"),
            play: newCommandArg(@["play"], playspec, help="Play a file"),
            help: newHelpArg()
        )

    test "Check help":
        let (success, message) = spec.parseOrMessage(args="-h", command="nimplayer")
        check(success and message.isSome)
        let expected = """
Usage:
  nimplayer play <filename>
  nimplayer (-h | --help)

Commands:
  play              Play a file

Options:
  -v, --verbose...  Verbosity
  -h, --help        Show help message""".strip()
        check(message.get==expected)

    test "Switch to the subcommand parser as soon as the command is seen":
        let (success, message) = spec.parseOrMessage(args="-v play -v -v rick.mp3", command="nimplayer")
        check(success and message.isNone)
        check(spec.verbose.seen)
        check(spec.verbose.count==1)
        check(spec.play.seen)
        check(playspec.volume.seen)
        check(playspec.volume.count==2)

    test "Short options can be repeated":
        let (success, message) = spec.parseOrMessage(args="-vv play rick.mp3", command="nimplayer")
        check(success and message.isNone)
        check(spec.verbose.seen)
        check(spec.verbose.count==2)
    
    test "Undefined short options are rejected":
        expect(ParseError):
            spec.parse(args="-w play rick.mp3", command="nimplayer")

    test "Undefined long options are rejected":
        expect(ParseError):
            spec.parse(args="--werbose play rick.mp3", command="nimplayer")

    test "Undefined coalesced options are rejected":
        expect(ParseError):
            spec.parse(args="-vvw play rick.mp3", command="nimplayer")

    test "Values that take options cannot be coalesced":
        expect(ParseError):
            spec.parse(args="play -vs rick.mp3", command="nimplayer")

    test "-- terminates options":
        spec.parse(args="play -- -v", command="nimplayer")
        check(spec.play.seen)
        check(playspec.filename.seen)
        check(playspec.filename.value=="-v")