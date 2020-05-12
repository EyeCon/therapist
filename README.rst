Therapist
=========

A type safe commandline parser, similar to  but less magic, with beautiful help messages.

.. image:: https://img.shields.io/bitbucket/pipelines/maxgrenderjones/therapist

A simple 'Hello world' example:

.. code:: nim
   :test:

   import therapist
   let spec = (
       # Name is an argument
       name: newStringArg(@["<name>"], help="Person to greet"),
       # --times will cause 0.1.0 to be printed
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

.. code:: sh

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

Many more examples are availbale in the source code and in the nimdoc

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