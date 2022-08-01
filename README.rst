Therapist_ - for when commands and arguments are getting you down
=================================================================

A simple to use, declarative, type-safe command line parser, with beautiful help messages and clear
errors, suitable for simple scripts and complex tools.

.. image:: https://img.shields.io/bitbucket/pipelines/maxgrenderjones/therapist


Therapist allows you to use a carefully constructed ``tuple`` to specify how you want your commandline 
arguments to be parsed. Each value in the tuple must be set to a ``<Type>Arg`` of the appropriate type, which
specifies how that argument will appear, what values it can take and provides a help string for the user.

Features:
---------

- Type-safe - Therapist will check that supplied values are of the expected type and makes defining your own types easy
- Approachable - Therapist provides only one macro which you may never need to use
- Powerful - Therapist has patterns for both single-file scripts and scripts with multiple commands split between files (e.g. ``git``)
- Flexible - Supports defaults, choices, using default values from environment variables, options that are not shown in help messages, required options and optional arguments
- Batteries-included - Generates beautiful (short and long-form) help messages, though you are free to roll your own (also provides fish-shell completions)
- Conventional - Follows standard conventions:  ``--yes/no`` or ``--[no-]format`` as variants imply what you would expect
- Helpful - Intelligent suggestions ``git blme`` -> did you mean ``git blame``?
- Tested - Therapist has lots of tests, many of which function as usage examples

A simple 'Hello world' example:

.. code-block:: nim

    import therapist

    # The parser is specified as a tuple
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
    # `args` and `command` are included in tests but would normally be picked up from the commandline
    spec.parseOrQuit(prolog="Greeter", args="-t 2 World", command="hello")
    # If a help message or version was requested or a parse error generated it would be printed
    # and then the parser would call `quit`. Getting past `parseOrQuit` implies we're ok.
    # `spec` has now been modified to reflect the supplied arguments
    for i in 1..spec.times.value:
        echo "Hello " & spec.name.value

    doAssert spec.name.seen
    doAssert spec.name.value == "World"
    doAssert spec.times.seen
    doAssert spec.times.value == 2


The above parser generates the following help message

.. code-block:: sh

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
      -h, --help           Show help message

The constructor for each ``<Type>Arg`` type takes the form:

.. code-block:: nim

  # doctest: skip
  proc newStringArg*(variants: seq[string], help: string, defaultVal="", choices=newSeq[string](),
                      helpvar="", required=false, optional=false, multi=false, env="", helpLevel=0)

- Every argument must be declared with one or more ``variants``. There are three types of argument:
   * Positional Arguments are declared in ``variants`` as ``<value>`` whose value is determined by 
     the order of arguments provided. They are required unless ``optional=true``
   * Optional Arguments are declared in ``variants`` as ``-o`` (short form) or ``--option`` (long form)
     which may take an argument or simply be counted. They are optional unless ``required=true``
   * Commands (declared in variants as ``command``) are expected to be entered by the user as written.
     The remainder of the arguments are parsed by a subparser which may have a different specification
     to the main parser
- Options may be interleaved with arguments, so ``> markup input.txt -o output.html`` is the same as
  ``> markup -o output.html input.txt``
- Options that take a value derive from ``ValueArg`` and may be entered as ``-o <value>``, ``-o:<value>`` 
  or ``-o=<value>`` (similarly for the long form i.e. ``--option <value>`` etc). Short options that
  do not take a value may be repeated, e.g. ``-vvv`` and short options can take values without a 
  separator e.g. ``-o<value>``
- A ``CountArg`` is a special type of ``Arg`` that counts how many times it is seen, without taking a 
  value (sometimes called a flag).
- ``CountArg`` also allows some special variant formats. If you specify ``--[no]option``, then 
  ``--option`` will count upwards (``args.count>0``) and ``--nooption`` will count downwards 
  (``args.count<0``). Alternatively ``-y/-n`` or ``--yes/--no`` will count upwards for ``-y`` or
  ``--yes`` and downwards for ``-n`` or ``--no``. Note that ``args.seen`` will return ``true`` if 
  ``args.count!=0``.
- If a command is seen, parsing will switch to that command immediately. So in ``> pal --verbose push --force``,
  the base parser receives ``--verbose``, and the ``push`` command parser receives ``--force``
- If an argument has been seen ``arg.seen`` will return ``true``. The values will also be entered
  into a ``values`` ``seq``, with the most recently seen value stored in ``value``. The number of 
  times the argument has been seen can be found in ``arg.count``
- If ``--`` is seen, the remainder of the arguments will be taken to be positional arguments, even
  if they look like options or commands
- A ``defaultVal`` value may be provided in case the argument is not seen. Additionally an ``env`` 
  key can be provided (e.g. ``env=USER``). If ``env`` is set to a key that is set in the environment,
  the default value will be set to that value e.g. ``$USER``).
- Arguments are expected to be seen at most once, unless ``multi=true``
- If there are only a set number of acceptable values for an argument, they can be listed in
  ``choices``
- A ``helpvar`` may be provided for use in the autogenerated help (e.g. ``helpvar="n"`` would lead 
  to a help message saying ``--number=<n>``)
- Within the help message, arguments are usually grouped into ``Commands``, ``Arguments`` and 
  ``Options``. If you want to group them differently, use the ``group`` parameter to define new 
  groups. Groups and arguments will be shown the order that they are appear in the tuple definition.
- If ``helpLevel`` is set to a value ``x`` greater than 0 the argument will only be shown in a help 
  message if the ``HelpArg`` is defined ``showLevel`` set to a value greater than or equal to ``x``
- If you want to define a new ``ValueArg`` type ``defineArg`` is a macro that will fill in the
  boilerplate for you

Argument types provided out of the box
--------------------------------------

- ``ValueArg`` - base class for arguments that take a value
   * ``StringArg`` - expects a string
   * ``IntArg`` - expects an integer
   * ``FloatArg`` - expects a floating point number
   * ``BoolArg`` - expects a boolean (on/off, true/false)
   * ``FileArg`` - expects a string argument that must point to an existing file
   * ``DirArg`` - expects a string argument that must point to an existing directory
   * ``PathArg`` - expects a string that must point to an existing file or directory
- ``CountArg`` - expects no value, simply counts how many times the argument is seen
- ``HelpArg`` - if seen, prints an auto-generated help message
- ``FishCompletionArg`` - if seen, prints a fish completion script
- ``MessageArg`` - if seen, prints a message (e.g. version number)

Creating your own argument type
-------------------------------

Creating your own ``ValueArg`` is as simple as defining a ``parse`` method that turns a ``string`` 
into a value of an appropriate type (or raises a ``ValueError`` for invalid input). Suppose we want 
to create a ``DateArg`` type that only accepts ISO-formatted dates:

.. code-block:: nim

    import therapist
    import times

    let DEFAULT_DATE = initDateTime(1, mJan, 2000, 0, 0, 0, 0)
    proc parseDate(value: string): DateTime = parse(value, "YYYY-MM-dd")
    defineArg[DateTime](DateArg, newDateArg, "date", DateTime, parseDate, DEFAULT_DATE)

Now we can call ``newDateArg`` to ask the user to supply a date

Examples
--------

At the other extreme, you can create complex parsers with subcommands (the example below may be 
familiar to those who have seen `docopt.nim`_). Note that the help message is slightly different; 
this is in part because parser itself is stricter. For example, ``--moored`` is only valid inside 
the ``mine`` subcommand, and as such, will only appear in the help for that command, shown if you
run ``navel_fate mine --help``.

.. code-block:: nim

   import options
   import strutils
   import therapist

   let prolog = "Navel Fate."
        
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
         help: newHelpArg()
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


Many more examples are available in the source code and in the nimdoc_ for the various functions.

Possible features therapist does not have
-----------------------------------------

In *rough* order of likelihood of being added:

- Ints and floats being limited to a range rather than a set of discrete values
- Support for ``+w`` and ``-w`` to equate to ``w=true`` and ``w=false``
- Generation of ``bash`` / ``powershell`` completion scripts
- Dependent option requirements i.e. because ``--optionA`` appears, ``--optionB`` is required
- Case/style insensitive matching
- Partial matches for ``commands`` i.e. ``pal pus`` is the same as ``pal push``, if that is the 
  only unambiguous match
- Support for alternate option characters (e.g. /) or different option semantics (e.g. java-style 
  single `-` ``-option``)

Installation
------------

Clone the repository and then run:

.. code:: sh

   > nimble install

Contributing
------------

The code lives on `bitbucket`_. Pull requests (with tests) and bug reports welcome!

Compatibility
-------------

For now, tests are run against the latest stable version of the 1.0.x, 1.2.x, 1.4.x and 1.6.x branches. Dropping support for
earlier verions may be considered for future releases, but only if it adds meaningful functionality / simplicity / maintainability.

Internally, `Therapist_` uses CamelCase.

License
-------

This library is made available under the LGPL. Use it to make any software you like, open source or not, 
but if you make improvements to therapist itself, please contribute them back.


Alternatives and prior art
--------------------------

This is therapist. There are many argument parsers like it, but this one is mine. Which one you 
prefer is likely a matter of taste. If you want to explore alternatives, you might like to look at:

- parseopt_ - for if you like to parse your args as they are flung at you, old school style
- `nim-argparse`_ - looks nice, but heavy use of macros, which makes it a little too magic for me
- `docopt.nim`_ - you get to craft your help message, but how you use the results (and indeed what
  the spec actually means) has always felt inscrutable to me
- cligen_ - *the* fastest way to generate a commandline parser if you already have the function you 
  want (think argh_ from python for nim). More complex use cases look a bit less elegant to my eyes, 
  but you're still going to be winning the code golf competition

.. include:: CHANGELOG.rst

.. _bitbucket: https://bitbucket.org/maxgrenderjones/therapist
.. _parseopt: https://nim-lang.org/docs/parseopt.html
.. _nim-argparse: https://github.com/iffy/nim-argparse
.. _docopt.nim: https://github.com/docopt/docopt.nim
.. _nimdoc: https://maxgrenderjones.bitbucket.io/therapist/latest/therapist.html
.. _Therapist: https://maxgrenderjones.bitbucket.io/therapist/latest/therapist.html
.. _cligen: https://github.com/c-blake/cligen
.. _argh: https://pythonhosted.org/argh/