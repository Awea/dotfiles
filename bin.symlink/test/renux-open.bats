#!/usr/bin/env bats
# Tests of renux-open, with a fake md-tui and a fake Fresh that write their arguments.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  RO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/renux-open"
  LOG="$BATS_TEST_TMPDIR/log"
  for prog in mdt fresh; do
    # shellcheck disable=SC2016 # The fake expands $EDITOR and $@ when it runs.
    printf '#!/bin/sh\n{ printf "%%s" "%s EDITOR=$EDITOR"; printf " [%%s]" "$@"; echo; } >>"%s"\n' \
      "$prog" "$LOG" >"$BATS_TEST_TMPDIR/$prog"
    chmod +x "$BATS_TEST_TMPDIR/$prog"
  done
  export MDT_BIN="$BATS_TEST_TMPDIR/mdt" FRESH_BIN="$BATS_TEST_TMPDIR/fresh"
  unset EDITOR
}

@test "the peek opens a markdown file in md-tui, with renux-open as its editor" {
  run "$RO" view 12 "notes/a b.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "mdt EDITOR=$RO [notes/a b.md]" ]
}

@test "the markdown extension can be in capitals or long" {
  "$RO" view 1 README.MD
  "$RO" view 1 doc.markdown
  [ "$(grep -c '^mdt ' "$LOG")" -eq 2 ]
}

@test "the peek opens another file in Fresh at its line" {
  run "$RO" view 42 src/main.zig
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "fresh EDITOR= [src/main.zig:42]" ]
}

@test "the e key of md-tui opens Fresh at the line on screen" {
  run "$RO" +14 notes/a.md
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "fresh EDITOR= [notes/a.md:14]" ]
}

@test "an editor call with no line opens Fresh on the file" {
  run "$RO" notes/a.md
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "fresh EDITOR= [notes/a.md]" ]
}

@test "a usage error exits 2 and starts nothing" {
  run "$RO" view 12
  [ "$status" -eq 2 ]
  run "$RO"
  [ "$status" -eq 2 ]
  [ ! -e "$LOG" ]
}
