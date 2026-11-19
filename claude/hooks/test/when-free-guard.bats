#!/usr/bin/env bats
# Tests for claude/hooks/when-free-guard.py.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/hooks/test/

SCRIPT="$BATS_TEST_DIRNAME/../when-free-guard.py"

# guard COMMAND: run the hook on a Bash tool call with COMMAND.
guard() {
  jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/in.json"
  run python3 "$SCRIPT" < "$BATS_TEST_TMPDIR/in.json"
}

refused() {
  [ "$status" -eq 2 ] || { echo "status $status, output: $output"; return 1; }
  [[ "$output" == *"Put ~/.bin/when-free before it"* ]]
}

allowed() {
  [ "$status" -eq 0 ] || { echo "status $status, output: $output"; return 1; }
  [ -z "$output" ]
}

@test "refuses mix test" {
  guard "mix test"
  refused
}

@test "refuses mix dialyzer in a rex run" {
  guard "rex run -s main --focus=false --keep-open --interactive --label t --cwd /tmp/x --json -- mix dialyzer"
  refused
}

@test "refuses mix compile after cd" {
  guard "cd /tmp/x && MIX_ENV=test mix compile --warnings-as-errors"
  refused
}

@test "refuses env MIX_ENV=test mix test" {
  guard "env MIX_ENV=test mix test test/foo_test.exs"
  refused
}

@test "refuses mix test in bash -c" {
  guard "rex run -s main --focus=false --keep-open --interactive --label t --cwd /tmp/x --json -- bash -c 'mix deps.get && mix test'"
  refused
}

@test "refuses mix test in a rex run" {
  guard "rex run -s main --label t --cwd /tmp/x --json -- mix test"
  refused
}

@test "refuses mix do with a heavy task" {
  guard "mix do compile, test"
  refused
}

@test "refuses mix coveralls and mix test.watch" {
  guard "mix coveralls.html"
  refused
  guard "mix test.watch"
  refused
}

@test "refuses the second command when only the first has when-free" {
  guard "when-free mix test && mix dialyzer"
  refused
}

@test "refuses mix test after a timeout prefix" {
  guard "timeout 600 mix test"
  refused
}

@test "allows when-free mix test" {
  guard "~/.bin/when-free mix test"
  allowed
}

@test "allows when-free env MIX_ENV=test mix test in a rex run" {
  guard "rex run -s main --focus=false --keep-open --interactive --label t --cwd /tmp/x --json -- ~/.bin/when-free env MIX_ENV=test mix test"
  allowed
}

@test "allows when-free bash -c with mix" {
  guard "rex run -s main --focus=false --keep-open --interactive --label t --cwd /tmp/x --json -- ~/.bin/when-free bash -c 'mix compile && mix test 2>&1 | tee /tmp/t.log'"
  allowed
}

@test "allows light mix tasks" {
  guard "mix format --check-formatted && mix deps.get && mix help test"
  allowed
}

@test "allows mix in text that runs no mix" {
  guard "git commit -m 'run mix test before a push' && grep -rn 'mix test' docs && echo mix test"
  allowed
}

@test "allows a command with no mix" {
  guard "ls -la"
  allowed
}

@test "allows a call that it cannot parse" {
  guard "echo 'no end quote"
  allowed
}

@test "allows an input with no command" {
  run python3 "$SCRIPT" <<<'{"tool_name": "Read", "tool_input": {}}'
  allowed
}

@test "refuses mix test on the line after a comment" {
  guard $'cd /tmp/x # go there\nmix test'
  refused
  guard $'echo when-free # x\nmix test'
  refused
}

@test "allows when-free on a line that a backslash continues" {
  guard $'~/.bin/when-free \\\n  env MIX_ENV=test mix test'
  allowed
  guard $'rex run -s main --focus=false --keep-open --interactive --label t --cwd /tmp/x --json -- ~/.bin/when-free \\\n  mix dialyzer'
  allowed
}

@test "refuses mix test when when-free comes after it" {
  guard "mix test --exclude when-free"
  refused
}

@test "refuses mix after the options of a prefix word" {
  guard "xargs -n1 mix test"
  refused
  guard "nice -n 10 mix compile"
  refused
}

@test "refuses mix test in bash -x -c" {
  guard "bash -x -c 'mix test'"
  refused
}

@test "refuses tasks that compile the project" {
  for c in "mix" "mix run priv/seed.exs" "mix phx.server" "iex -S mix phx.server" "mix escript.build"; do
    guard "$c"
    refused
  done
}

@test "allows mix after the options of a word that runs no mix" {
  guard "grep -A 3 mix test.log"
  allowed
}
