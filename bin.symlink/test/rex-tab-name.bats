#!/usr/bin/env bats
# Tests of rex-tab-name, with the fake rex of the board-orchestrator tests.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  TN="$BATS_TEST_DIRNAME/../rex-tab-name"
  FAKE="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fake-rex"
  export REX_BIN="$FAKE"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake" FAKE_LOG="$BATS_TEST_TMPDIR/log"
  mkdir -p "$FAKE_DIR"
  : >"$FAKE_LOG"
  unset BOARD BOARD_ROLE
  new=$("$FAKE" new garden)
  export REX_SESSION REX_BLOCK
  REX_SESSION=$(jq -r .session_id <<<"$new")
  REX_BLOCK=$(jq -r '.initial_windows[0].block_ids[0]' <<<"$new")
  WINDOW=$(jq -r '.initial_windows[0].window_id' <<<"$new")
  : >"$FAKE_LOG"
}

@test "renames the window of REX_BLOCK" {
  run "$TN" rex-tab-names
  [ "$status" -eq 0 ]
  grep -qF "rex window rename -s $REX_SESSION $WINDOW rex-tab-names" "$FAKE_LOG"
}

@test "does nothing outside Rex" {
  unset REX_BLOCK
  run "$TN" rex-tab-names
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}


@test "does nothing in a board worker" {
  export BOARD=garden BOARD_ROLE=worker
  run "$TN" rex-tab-names
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "an empty name is a usage error" {
  run "$TN" ""
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "a Rex failure exits 1" {
  export FAKE_REX_FAIL=1
  run "$TN" rex-tab-names
  [ "$status" -eq 1 ]
}
