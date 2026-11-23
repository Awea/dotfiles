#!/usr/bin/env bats
# dispatch.sh view-check: the orchestrator checks that a start request comes from the board
# view pane of its own window, before it starts a worker (SKILL.md rule 6).

bats_require_minimum_version 1.5.0
load helper

O=block:01a1ef15-4833-735e-9530-226d79648a16
V=block:01a1ef2a-0000-7000-8000-0000b0a2d001
SH=/nix/store/hasnvc0j36gg6qrdsfcx7yivx3c2bpqr-bash-5.3p20/bin/sh
WRAPPED=/nix/store/fnsp5048h1bvan7df7l02ig9k96yh84s-board-0.1.0/bin/.board-view-wrapped

setup() {
  rex_setup
  rex_orchestrator "$O" garden
}

teardown() { [ -z "${PANE_PID:-}" ] || kill "$PANE_PID" 2>/dev/null || true; }

dispatch() { run bash "$SKILL_DIR/dispatch.sh" "$@"; }

# pane_process ARGS: a live process whose command line is ARGS, as ps shows it. Its pid
# goes into the Rex process answer of the block V, in the shape of the real answer.
pane_process() {
  perl -e '$0 = shift; sleep 60' "$1" &
  PANE_PID=$!
  sleep 0.2
  jq --argjson p "$PANE_PID" '.child.pid = $p' "$SKILL_DIR/test/fixtures/rex/process-board-view.json" \
    >"$FAKE_DIR/rex/process-$V.json"
}

# view_block SESSION WINDOW LABEL: the live block V, with a block label.
view_block() {
  jq -cn --arg s "$1" --arg b "$V" --arg w "$2" --arg l "$3" \
    '{session_id:$s, window_id:$w, window_label:"orchestrator", label:$l, block_id:$b}' \
    >>"$FAKE_DIR/rex/blocks.jsonl"
}

@test "view-check accepts the board view pane of the window of the orchestrator" {
  view_block session:fake-1 window:fake-1 "board view"
  pane_process "$SH $WRAPPED garden"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 0 ]
  [ "$output" = "view-check: ok" ]
}

@test "view-check refuses a board view tab that a worker opened in another window" {
  view_block session:fake-1 window:job-1 "board view"
  pane_process "$SH $WRAPPED garden"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not in the window of this orchestrator"* ]]
}

@test "view-check refuses a block of the window with another label" {
  view_block session:fake-1 window:fake-1 "shell"
  pane_process "$SH $WRAPPED garden"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a board view pane"* ]]
}

@test "view-check refuses a pane with a program named board outside the Nix store" {
  view_block session:fake-1 window:fake-1 "board view"
  pane_process "/bin/sh $HOME/work/bin/.board-view-wrapped garden"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not run the board view of the board garden"* ]]
}

@test "view-check refuses the board view of another board" {
  view_block session:fake-1 window:fake-1 "board view"
  pane_process "$SH $WRAPPED perso"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not run the board view of the board garden"* ]]
}

@test "view-check refuses a Claude Code block with the board view label" {
  view_block session:fake-1 window:fake-1 "board view"
  cp "$SKILL_DIR/test/fixtures/rex/process-claude.json" "$FAKE_DIR/rex/process-$V.json"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not run the board view"* ]]
}

@test "view-check refuses a board view pane of another session" {
  view_block session:other window:fake-1 "board view"
  pane_process "$SH $WRAPPED garden"
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no live block"* ]]
}

@test "view-check refuses a block that is gone" {
  dispatch view-check "${V: -8}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no live block"* ]]
}

@test "view-check refuses a short ID with less than 8 characters" {
  view_block session:fake-1 window:fake-1 "board view"
  dispatch view-check d001
  [ "$status" -eq 2 ]
}

@test "view-check runs only in an orchestrator in Renux" {
  unset REX_SESSION
  dispatch view-check "${V: -8}"
  [ "$status" -eq 2 ]
}
