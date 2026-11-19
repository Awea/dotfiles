#!/usr/bin/env bats
# Tests of rex-summary. REX_SUMMARY_TTY sends the report to a file in place of the terminal,
# so that no test writes to the real pane.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  RS="$BATS_TEST_DIRNAME/../rex-summary"
  OUT="$BATS_TEST_TMPDIR/tty"
  : >"$OUT"
  unset HC_TERMINAL_ID
  export REX_BLOCK=block:fake REX_SUMMARY_TTY="$OUT"
}

# msg_of FILE: the decoded msg of the report in FILE.
msg_of() {
  sed -n 's/.*:msg=\([A-Za-z0-9+\/=]*\).*/\1/p' "$1" | base64 -d
}

@test "writes an OSC 7501 summary record" {
  run "$RS" "Patches the Renux sidebar"
  [ "$status" -eq 0 ]
  [ "$(head -c 9 "$OUT" | od -An -c | tr -d ' ')" = '033]7501;id' ]
  grep -qF ';id=summary:state=idle:msg=' "$OUT"
  [ "$(tail -c 2 "$OUT" | od -An -c | tr -d ' ')" = '033\' ]
  [ "$(msg_of "$OUT")" = "Patches the Renux sidebar" ]
}

@test "keeps UTF-8 and joins the words" {
  run "$RS" Répare la "barre ✅"
  [ "$status" -eq 0 ]
  [ "$(msg_of "$OUT")" = "Répare la barre ✅" ]
}

@test "removes control characters" {
  run "$RS" "$(printf 'one\ttwo\nthree')"
  [ "$status" -eq 0 ]
  [ "$(msg_of "$OUT")" = "onetwothree" ]
}

@test "does nothing outside Rex" {
  unset REX_BLOCK
  run "$RS" "Patches the Renux sidebar"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
}

@test "does nothing in herdr-app" {
  export HC_TERMINAL_ID=t7
  run "$RS" "Patches the Renux sidebar"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
}

@test "an empty sentence is a usage error" {
  run "$RS" ""
  [ "$status" -eq 2 ]
  [ ! -s "$OUT" ]
}

@test "a sentence over 2048 bytes is cut on a character" {
  long=$(printf 'é%.0s' $(seq 1 1500))
  run "$RS" "$long"
  [ "$status" -eq 0 ]
  m=$(msg_of "$OUT")
  [ "$(printf %s "$m" | wc -c)" -le 2048 ]
  printf %s "$m" | iconv -f UTF-8 -t UTF-8 >/dev/null
}

@test "no terminal is an error" {
  unset REX_SUMMARY_TTY
  export REX_SUMMARY_PID=1
  run "$RS" "Patches the Renux sidebar"
  [ "$status" -eq 1 ]
}
