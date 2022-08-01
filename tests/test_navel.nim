import strutils
import unittest

import ../src/therapist

suite "Navel Fate":
    ## An intepretation of what the naval fate docopt example is intended to do
    
    let prolog = "Navel Fate."
    
    setup:
        let create = (
            name: newStringArg(@["<name>"], multi=true, help="Name of new ship")
        )
        let move = (
            name: newStringArg(@["<name>"], help="Name of ship to move"),
            x: newIntArg(@["<x>"], help="x grid reference"),
            y: newIntArg(@["<y>"], help="y grid reference"),
            speed: newIntArg(@["--speed"], defaultVal=10, help="Speed in knots"),
            help: newHelpArg()
        )
        let shoot = (
            x: newIntArg(@["<x>"], help="Name of new ship"),
            y: newIntArg(@["<y>"], help="Name of new ship"),
        )
        let state = (
            moored: newCountArg(@["--moored"], help="Moored (anchored) mine"),
            drifting: newCountArg(@["--drifting"], help="Drifting mine"),
        )
        let mine = (
            action: newStringArg(@["<action>"], choices = @["set", "remove"], help="Action to perform"),
            x: newIntArg(@["<x>"], help="Name of new ship"),
            y: newIntArg(@["<y>"], help="Name of new ship"),
            state: state,
            help: newHelpArg()
        ) ## Todo: set or remove

        let ship = (
            create: newCommandArg(@["new"], create, help="Create a new ship"),
            move: newCommandArg(@["move"], move, prolog="Command to move your ship", help="Move a ship"),
            shoot: newCommandArg(@["shoot"], shoot, help="Shoot at another ship"),
            help: newHelpArg()
        )

        let spec = (
            ship: newCommandArg(@["ship"], ship, help="Ship commands"),
            mine: newCommandArg(@["mine"], mine, help="Mine commands"),
            help: newHelpArg()
        )
    
    test "Fate Help":
        try:
            parse(spec, args="-h", prolog=prolog, command="navel_fate")
        except MessageError:
            let message = getCurrentExceptionMsg()
            let expected = """
Navel Fate.

Usage:
  navel_fate ship new <name>...
  navel_fate ship move <name> <x> <y>
  navel_fate ship shoot <x> <y>
  navel_fate mine (set|remove) <x> <y>
  navel_fate -h|--help

Commands:
  ship        Ship commands
  mine        Mine commands

Options:
  -h, --help  Show help message""".strip()
            if len(expected)==0:
                skip()
            else:
                check(message==expected)
    
    test "Ship move help":
        let (success, message) = parseOrMessage(spec, args="ship move -h", prolog=prolog, command="navel_fate")
        check(success)
        check(message.isSome)
        let expected = """
Command to move your ship

Usage:
  navel_fate ship move <name> <x> <y>
  navel_fate ship move -h|--help

Arguments:
  <name>               Name of ship to move
  <x>                  x grid reference
  <y>                  y grid reference

Options:
      --speed=<speed>  Speed in knots [default: 10]
  -h, --help           Show help message""".strip
        check(message.get==expected)


    test "Multiple values captured correctly":
        parse(spec, args="ship new victory titanic", command="navel_fate")
        check(spec.ship.seen)
        check(ship.create.seen)
        check(create.name.value == "titanic")
        check(create.name.values == @["victory", "titanic"])

    test "Nested subcommands parse correctly":
        parse(spec, args="ship move victory 1 9", command="navel_fate")
        check(spec.ship.seen)
        check(ship.move.seen)
        check(move.name.value=="victory")
        check(move.x.value==1)
        check(move.y.value==9)
    
    test "Constrained values are enforced":
        expect(ParseError):
            parse(spec, args="mine add 1 9", command="navel_fate")

    test "Constrained values parse correctly":
        parse(spec, args="mine set 1 9", command="navel_fate")
        check(spec.mine.seen)
        check(mine.action.value=="set")
        check(mine.x.value==1)
        check(mine.y.value==9)
