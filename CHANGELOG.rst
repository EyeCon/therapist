Changes
-------

0.3.0
^^^^^

- Breaking: Use a macro for ``defineArg`` to allow generated constructors to have documentation (requires ``ArgType`` parameter)
- Breaking: Pass specification parameter to ``register`` method.
- Generate completion scripts for fish shell
- Options that can be repeated show ``...`` in their help text
- Add ``newFlagArg`` as an alias for ``newCountArg`` with ``multi=false``
- Support paragraph-style help output by setting ``helpStyle=HelpStyle.hsParagraphs`` on help args, using ``longHelp`` parameter if present

0.2.0 2022-07-16
^^^^^^^^^^^^^^^^

- Breaking: Switch to using ``defaultVal`` consistently everywhere (previously, some used ``default``)
- Add ``parseCopy`` to get back a copy of your specification rather than a modified one
- Add ``parseOrHelp`` to show both error and help message on ParseError (@squattingmonk)
- Add support for ``--[no-]colour`` as well as ``--[no]colour`` (idea from @squattingmonk)
- Added convenience versions of ``newXXXArg`` where ``variants`` can be provided as a comma-separated string
- Add ``newHelpCommandArg`` and ``newMessageCommandArg``

0.1.0 2020-05-23
^^^^^^^^^^^^^^^^

Initial release