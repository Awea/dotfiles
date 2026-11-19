#!/usr/bin/env python3
"""PreToolUse hook (Bash): refuse a heavy mix build or test without when-free.

A dialyzer PLT build without when-free used 19 GB, and the host ran out of memory.
The hook reads the Bash command and finds each mix call at a command position: the
start of a command, after VAR=value words, after a prefix word (env, time, nohup,
xargs...) and its options, or after `--` (rex run). When the mix task is heavy
(test, compile, dialyzer, run, phx.server, release...) and no when-free word comes
before it in that command, exit 2 refuses the call. A bare `mix` and `iex -S mix` are
heavy too. The hook also reads the shell line of `bash -c '...'`.

A command that the hook cannot parse goes through: the hook only stops the usual
mistake. Known gaps: `sudo -u USER mix test` and `x="$(mix test)"` go through, and a
heredoc body or `grep -- mix test` is refused. Python 3.8 or later (shlex splits at
punctuation_chars from 3.8), no packages: it runs on Linux and macOS.
"""

import json
import re
import shlex
import sys

PUNCTUATION = "();<>|&\n"
SHELLS = {"bash", "sh", "zsh", "dash"}
PREFIXES = {
    "env", "time", "nohup", "exec", "command", "sudo", "nice", "xargs",
    "do", "then", "else", "!", "{", "timeout",
}
HEAVY = re.compile(
    r"^(test|compile|deps\.compile|dialyzer|coveralls|release|check|ci|precommit"
    r"|run|phx\.server|escript\.build|docs)(\..*)?$"
)
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
NUMBER = re.compile(r"^[0-9]+(\.[0-9]+)?[smhd]?$")


def base(word):
    return word.rsplit("/", 1)[-1]


def tokens(command):
    # A backslash and a newline join two lines. A comment runs to the end of its
    # line: the hook drops it, but keeps the newline that ends the command.
    command = command.replace("\\\n", " ")
    lexer = shlex.shlex(command, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    words, comment = [], False
    for word in lexer:
        if word == "\n":
            comment = False
        elif comment or word.startswith("#"):
            comment = True
            continue
        words.append(word)
    return words


def segments(words):
    """Split the words at the control operators: ; && || | ( ) and newlines."""
    segment = []
    for word in words:
        if word and all(c in PUNCTUATION for c in word):
            if segment:
                yield segment
            segment = []
        else:
            segment.append(word)
    if segment:
        yield segment


def command_position(segment, i):
    """True when segment[i] is the program of a command."""
    j = i - 1
    while j >= 0 and ASSIGNMENT.match(segment[j]):
        j -= 1
    if j < 0 or segment[j] == "--":
        return True
    # A prefix word (xargs -n1, nice -n 10, timeout 600) runs the words after its
    # options. Options and numbers after another word (grep -A 3) are its arguments.
    while j >= 0 and segment[j] != "--" and (
        segment[j].startswith("-") or NUMBER.match(segment[j])
    ):
        j -= 1
    return j >= 0 and base(segment[j]) in PREFIXES


def heavy(task, rest):
    if task is None:
        return True
    if HEAVY.match(task):
        return True
    if task == "do":
        names = [n.strip() for w in rest for n in w.split(",")]
        return any(HEAVY.match(n) for n in names if n and n != "+")
    return False


def find_heavy_mix(command):
    """Return the first heavy mix call without when-free, or None."""
    for segment in segments(tokens(command)):
        for i, word in enumerate(segment):
            if base(word) == "when-free":
                break
            nxt = segment[i + 1] if i + 1 < len(segment) else None
            if base(word) in SHELLS and command_position(segment, i):
                found = shell_line(segment[i + 1:])
                if found:
                    return found
            if base(word) == "iex" and segment[i + 1:i + 3] == ["-S", "mix"]:
                return " ".join(segment[i:i + 4])
            if base(word) == "mix" and command_position(segment, i):
                if heavy(nxt, segment[i + 2:]):
                    return " ".join(["mix"] + segment[i + 1:i + 3])
    return None


def shell_line(args):
    """Check the shell line of `bash -x -c '...'`: the first word after the options."""
    has_c = False
    for arg in args:
        if arg.startswith("-") and not arg.startswith("--"):
            has_c = has_c or "c" in arg
            continue
        return find_heavy_mix(arg) if has_c else None
    return None


def main():
    try:
        data = json.load(sys.stdin)
        command = data.get("tool_input", {}).get("command")
        if not isinstance(command, str):
            return 0
        found = find_heavy_mix(command)
    except Exception:
        return 0
    if not found:
        return 0
    sys.stderr.write(
        "when-free-guard: `{}` is a heavy build or test. "
        "Put ~/.bin/when-free before it: `~/.bin/when-free mix test`, "
        "`~/.bin/when-free env MIX_ENV=test mix test` or "
        "`~/.bin/when-free bash -c '...'`. A dialyzer PLT build without when-free "
        "used 19 GB and the host ran out of memory.\n".format(found)
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
