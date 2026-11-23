#!/usr/bin/env bats
# board-view-open: ctrl+b w opens the board view only in the tab of a board orchestrator.

load helper

setup() {
  base_setup
  REC="$XDG_STATE_HOME/board-orchestrator-hc/rex"
  mkdir -p "$REC"
}

@test "an orchestrator block gives its board" {
  printf '{"board":"perso","role":"orchestrator","rex_session":"session:p"}' >"$REC/block:o.json"
  run "$BIN/board-view-open" block:o
  [ "$status" -eq 0 ]
  [ "$output" = perso ]
}

@test "a worker block exits 1" {
  printf '{"board":"perso","role":"worker"}' >"$REC/block:w.json"
  run "$BIN/board-view-open" block:w
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a block with no record exits 1" {
  run "$BIN/board-view-open" block:none
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a board name with other characters exits 1" {
  printf '{"board":"a\\"b","role":"orchestrator"}' >"$REC/block:o.json"
  run "$BIN/board-view-open" block:o
  [ "$status" -eq 1 ]
}

@test "a record with bad JSON exits 1" {
  printf '{bad' >"$REC/block:o.json"
  run "$BIN/board-view-open" block:o
  [ "$status" -eq 1 ]
}
