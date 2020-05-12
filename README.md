# Therapist

A type safe commandline parser, similar to [nim-argparse](https://github.com/iffy/nim-argparse) 
but less magic, with beautiful help messages.

[![Build Status](https://img.shields.io/bitbucket/pipelines/maxgrenderjones/therapist "Pielines build status")](https://bitbucket.org/maxgrenderjones/therapist/addon/pipelines/home)


```nim
let spec = (
    # Name is an argument
    name: newStringArg(@["<name>"], help="Person to greet"),
    # --version will cause 0.1.0 to be printed
    version: newMessageArg(@["--version"], "0.1.0", help="Prints version"),
    # --help will cause a help message to be printed
    help: newHelpArg(@["-h", "--help"], help="Show help message"),
)
# `args` and `command` would normally be picked up from the commandline
spec.parseOrQuit(prolog="Greeter", args="World", command="hello")
# If a help message or version was requested or a parse error generated it would be printed
# and then the parser would call `quit`. Getting past `parseOrQuit` implies we're ok.
echo "Hello " & spec.name.value
```

The above parser generates the following help message

```
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
```

Many more examples are availbale in the source code and in the nimdoc

## Installation

Clone the repository and then run:

```sh
> nimble install
```