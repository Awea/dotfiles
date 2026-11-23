#!/usr/bin/env bats
# Tests of rex-starter. REX_STARTER_TTY sends the record to a file in place of stdout, so
# that a test sees it apart from the output of the command.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  RS="$BATS_TEST_DIRNAME/../rex-starter"
  OUT="$BATS_TEST_TMPDIR/tty"
  : >"$OUT"
  unset REX_STARTER_TTY
}

# msg_of FILE: the decoded msg of the record in FILE.
msg_of() {
  sed -n 's/.*:msg=\([A-Za-z0-9+\/=]*\).*/\1/p' "$1" | base64 -d
}

@test "writes a starter record, then runs the command" {
  REX_STARTER_TTY="$OUT" run "$RS" block:abc echo hi
  [ "$status" -eq 0 ]
  [ "$output" = hi ]
  [ "$(head -c 9 "$OUT" | od -An -c | tr -d ' ')" = '033]7501;id' ]
  grep -qF ';id=starter:state=idle:msg=' "$OUT"
  # shellcheck disable=SC1003 # the text 033\ of od, no escaped quote
  [ "$(tail -c 2 "$OUT" | od -An -c | tr -d ' ')" = '033\' ]
  [ "$(msg_of "$OUT")" = block:abc ]
}

@test "an empty block only runs the command" {
  REX_STARTER_TTY="$OUT" run "$RS" "" echo hi
  [ "$status" -eq 0 ]
  [ "$output" = hi ]
  [ ! -s "$OUT" ]
}

@test "a stdout that is not a terminal gets no record" {
  run "$RS" block:abc echo hi
  [ "$status" -eq 0 ]
  [ "$output" = hi ]
}

@test "removes control characters from the block" {
  REX_STARTER_TTY="$OUT" run "$RS" "$(printf 'block:a\tb\n')" true
  [ "$status" -eq 0 ]
  [ "$(msg_of "$OUT")" = block:ab ]
}

@test "keeps each word of the command and its exit code" {
  run "$RS" block:abc printf '%s|' "a b" -D
  [ "$status" -eq 0 ]
  [ "$output" = 'a b|-D|' ]
  run "$RS" block:abc sh -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "no command is a usage error" {
  run "$RS" block:abc
  [ "$status" -eq 2 ]
}
