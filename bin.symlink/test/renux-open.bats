#!/usr/bin/env bats
# Tests of renux-open, with a fake Leaf and a fake Fresh that write their arguments.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/

setup() {
  RO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/renux-open"
  LOG="$BATS_TEST_TMPDIR/log"
  for prog in leaf fresh; do
    printf '#!/bin/sh\n{ printf "%%s" "%s"; printf " [%%s]" "$@"; echo; } >>"%s"\n' \
      "$prog" "$LOG" >"$BATS_TEST_TMPDIR/$prog"
    chmod +x "$BATS_TEST_TMPDIR/$prog"
  done
  export LEAF_BIN="$BATS_TEST_TMPDIR/leaf" FRESH_BIN="$BATS_TEST_TMPDIR/fresh"
}

@test "the peek opens a markdown file in Leaf" {
  run "$RO" view 12 "notes/a b.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "leaf [open] [notes/a b.md]" ]
}

@test "the markdown extension can be in capitals or long" {
  "$RO" view 1 README.MD
  "$RO" view 1 doc.markdown
  [ "$(grep -c '^leaf ' "$LOG")" -eq 2 ]
}

@test "the peek opens another file in Fresh at its line" {
  run "$RO" view 42 src/main.zig
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "fresh [src/main.zig:42]" ]
}

@test "a name with .md before its end opens in Fresh" {
  run "$RO" view 3 notes.md.orig
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "fresh [notes.md.orig:3]" ]
}

@test "a usage error exits 2 and starts nothing" {
  run "$RO" view 12
  [ "$status" -eq 2 ]
  run "$RO"
  [ "$status" -eq 2 ]
  run "$RO" +14 notes/a.md
  [ "$status" -eq 2 ]
  [ ! -e "$LOG" ]
}
