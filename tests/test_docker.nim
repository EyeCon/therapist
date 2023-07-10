import pegs
import strformat
import strutils
import unittest

import ../src/therapist

const PROLOG = "A self-sufficient runtime for containers"

let DETACH_PEG = peg"""
            arg <- {[a-z]} / (i'ctrl-' {value})
            value <- [a-z] / [@] / [^] / [\] / [_]
        """

proc parse_detach(val: string): string =
    # Define custom parsing function for valid values
    var key: array[1, string]
    if val.match(DETACH_PEG, key):
        return key[0]
    raise newException(ParseError, fmt"""Expected <value> as one of: a-z or ctrl-<value> where value is one of: a-z, @, ^, [ or _"), got '{val}'""")

#Create new type DetachArg with constructor newDetachArg to validate valid escape sequences
defineArg[string](DetachArg, newDetachArg, "escape sequence", string, parse_detach, defaultT="", comment="An argument to capture escape sequences")

suite "Docker commandline":
    setup:
        
        let PROXY_HELP = "Proxy all received signals to the process (non-TTY mode only), SIGCHLD, SIGKILL and SIGSTOP are not proxied."

        let attachSpec = (
            keys: newDetachArg("--detach-keys", help="Override the sequence for detatching a console"),
            help: newHelpArg(),
            stdin: newBoolArg("--no-stdin", help="Do not attach STDIN", defaultVal=false),
            proxy: newBoolArg("--sig-proxy", help=PROXY_HELP),
            container: newStringArg("<container>", help="Container to attach to")
        )

        let spec = (
            config: newStringArg("--config", defaultVal="/root/.docker", help="Location of client config files"),
            context: newStringArg("-c, --context", help="Name of the context to use to connect to the daemon"),
            debug: newFlagArg("-D, --debug", "Enable debug mode"),
            help: newHelpArg("--help", help="Print usage"),
            host: newStringArg("-H, --host", help="Daemon socket(s) to connect to"),
            log: newStringArg("-l, --log-level", help="Set the logging level", defaultVal="info", choices= @["debug", "info", "warn", "error", "fatal"]),
            tls: newFlagArg("--tls", help="Use TLS; implied by --tlsverify"),
            tlscacert: newStringArg("--tlscacert", help="Trust certs only signed by this CA", defaultVal="/root/.docker/ca.pem"),
            tlscert: newStringArg("--tlscert", help="Path to TLS certificate file", defaultVal="/root/.docker/cert.pem"),
            tlscakey: newStringArg("--tlskey", help="Path to TLS key file", defaultVal="/root/.docker/key.pem"),
            tlsverify: newStringArg("--tlsverify", help="Use TLS and verify the remote"),
            version: newMessageArg("-v, --version", message="0.1.0", help="Print version information and quit"),
            # Commands
            attach: newCommandArg("attach", attachSpec, "Attach to a running container")

        )

    test  "Help message":

        let expected = """
A self-sufficient runtime for containers

Usage:
  docker attach <container>
  docker (--help | -v | --version)

Commands:
  attach                       Attach to a running container

Options:
      --config=<config>        Location of client config files [default:
                               /root/.docker]
  -c, --context=<context>      Name of the context to use to connect to the
                               daemon
  -D, --debug                  Enable debug mode
      --help                   Print usage
  -H, --host=<host>            Daemon socket(s) to connect to
  -l, --log-level=<log-level>  Set the logging level [choices:
                               debug|info|warn|error|fatal] [default: info]
      --tls                    Use TLS; implied by --tlsverify
      --tlscacert=<tlscacert>  Trust certs only signed by this CA [default:
                               /root/.docker/ca.pem]
      --tlscert=<tlscert>      Path to TLS certificate file [default:
                               /root/.docker/cert.pem]
      --tlskey=<tlskey>        Path to TLS key file [default:
                               /root/.docker/key.pem]
      --tlsverify=<tlsverify>  Use TLS and verify the remote
  -v, --version                Print version information and quit
        """.strip()


        let parsed = spec.parseOrMessage(prolog=PROLOG, args="--help", command="docker")
        check(parsed.success)
        check(parsed.message.isSome)
        check(parsed.message.get == expected)

    test "Custom parser (success)":
        let parsed = spec.parseOrMessage(prolog=PROLOG, args="attach --detach-keys Ctrl-z some_container", command="docker")
        check(parsed.success)
        if parsed.message.isSome:
            echo parsed.message.get
        check(spec.attach.seen)
        check(attachSpec.keys.seen)
        check(attachSpec.keys.value=="z")
        check(attachSpec.container.seen)
        check(attachSpec.container.value=="some_container")

    test "Custom parser (failure)":
        let parsed = spec.parseOrMessage(prolog=PROLOG, args="attach --detach-keys [ some_container", command="docker")
        check(not parsed.success)
        check(parsed.message.isSome)
        check(parsed.message.get=="""Expected <value> as one of: a-z or ctrl-<value> where value is one of: a-z, @, ^, [ or _"), got '['""")
