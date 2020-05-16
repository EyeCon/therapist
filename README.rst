Therapist
=========

A simple to use, declarative, type-safe command line parser, striving for beautiful help messages.

.. image:: https://img.shields.io/bitbucket/pipelines/maxgrenderjones/therapist

A simple 'Hello world' example:

.. code-block:: nim

   import therapist

   # The parser is specified as a tuple
   let spec = (
       # Name is a positional argument, by virtue of being surrounded by < and >
       name: newStringArg(@["<name>"], help="Person to greet"),
       # --times is an optional argument, by virtue of starting with - and/or --
       times: newIntArg(@["-t", "--times"], default=1, help="How many times to greet"),
       # --version will cause 0.1.0 to be printed
       version: newMessageArg(@["--version"], "0.1.0", help="Prints version"),
       # --help will cause a help message to be printed
       help: newHelpArg(@["-h", "--help"], help="Show help message"),
   )
   # `args` and `command` would normally be picked up from the commandline
   spec.parseOrQuit(prolog="Greeter", args="-t 2 World", command="hello")
   # If a help message or version was requested or a parse error generated it would be printed
   # and then the parser would call `quit`. Getting past `parseOrQuit` implies we're ok.
   for i in 1..spec.times.value:
      echo "Hello " & spec.name.value
   
   doAssert spec.name.value == "World"
   doAssert spec.times.value == 2


The above parser generates the following help message

.. code-block:: sh

   Greeter

   Usage:
     hello <name>
     hello --version
     hello -h|--help

   Arguments:
     <name>      Person to greet

   Options:
     --version   Prints version
     -h, --help  Show help message


At the other extreme, you can create parsers with subcommands (see `docopt.nim`_). Note that the help message is slightly different;
this is in part because parser itself is stricter. For example, `--moored` is only valid inside the `mine` subcommand, and as such, 
will only appear in the help for that command, shown if you run `navel_fate mine --help`.

.. code-block:: nim

   import options
   import strutils
   import therapist

   let prolog = "Navel Fate."
        
   let create = (
         name: newStringArg(@["<name>"], multi=true, help="Name of new ship")
   )
   let move = (
         name: newStringArg(@["<name>"], help="Name of new ship"),
         x: newIntArg(@["<x>"], help="x grid reference"),
         y: newIntArg(@["<y>"], help="y grid reference"),
         speed: newIntArg(@["--speed"], default=10, help="Speed in knots [default: 10]")
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
   )

   let ship = (
         create: newCommandArg(@["new"], create, help="Create a new ship"),
         move: newCommandArg(@["move"], move, help="Move a ship"),
         shoot: newCommandArg(@["shoot"], shoot, help="Shoot at another ship"),
         help: newHelpArg()
   )

   let spec = (
         ship: newCommandArg(@["ship"], ship, help="Ship commands"),
         mine: newCommandArg(@["mine"], mine, help="Mine commands"),
         help: newHelpArg()
   )

   let (success, message) = spec.parseOrMessage(prolog="Navel Fate.", args="--help", command="navel_fate")

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

   doAssert success and message.isSome
   doAssert message.get == expected


Many more examples are available in the source code and in the nimdoc for the various functions.

Notes on parsing
----------------

- There are three types of argument:
      - Positional Arguments (declared in variants as `<value>`) whose value is determined by the order 
        of arguments provided
      - Optional Arguments (declared in variants as `-o` or `--option`) which may take an argument or 
        simply be counted
      - Commands (declared in variants as `command`) which start a subparser, which may take different
        options
- Options may be interleved with arguments, so `markup input.txt -o output.html` is the same as
`markup -o output.html input.txt`
- If a command is seen, parsing will switch to that command immediately. So in `pal --verbose push --force`,
the base barser receives `--verbose`, and the `push` comamnd parser receives `--force`
- If `--` is seen, the remainder of the arguments will be taken to be positional arguments, even if they 
look like options or commands
- `CountArg`'s short options may be coalesced together, but not options that taken an argument. i.e. `pal -vvv`
going to give you some *really* verbose output
- If you want to define a new value type `defineArg` is a template that will fill in the boilerplate for you

Possible features therapist does not have
-----------------------------------------

- The ability to specify options in the form `--[no]color` such that `--color` sets the value to `true` 
  and `--nocolor` to false
- 

Installation
------------

Clone the repository and then run:

.. code:: sh

   > nimble install

Alternatives and prior art
--------------------------

This is therapist. There are many argument parsers like it, but this one is mine. Which one you prefer is likely a matter of taste.
If you want to explore alternatives, you might like to look at:


- `nim-argparse`_ - looks nice, but heavy use of macros, which makes it a little too magic for my tastes
- `docopt.nim`_ - you get to craft your help message, but how you use the results (and what the spec actually means) has always felt inscrutable to me.

.. _nim-argparse: https://github.com/iffy/nim-argparse
.. _docopt.nim: https://github.com/docopt/docopt.nim