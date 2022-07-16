Changes
-------

0.2.0
^^^^^

- Breaking: Switch to using `defaultVal` consistently everywhere (previously, some used `default`)
- Add `parseCopy` to get back a copy of your specification rather than a modified one
- Add `parseOrHelp` to show both error and help message on ParseError (@squattingmonk)
- Add support for `--[no-]colour` as well as `--[no]colour` (idea from @squattingmonk)
- Added convenience versions of `newXXXArg` where `variants` can be provided as a comma-separated string
- Add `newHelpCommandArg` and `newMessageCommandArg`

0.1.0 2020-05-23
^^^^^^^^^^^^^^^^

Initial release