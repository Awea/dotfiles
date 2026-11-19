#!/usr/bin/env bats
load helper

source_lib() { source "$SKILL_DIR/lib.sh"; }

@test "has_labels is true for a live terminal of that board and role" {
  source_lib
  fake_terminal t5 garden worker
  run has_labels t5 garden worker
  [ "$status" -eq 0 ]
}

@test "has_labels is false for another board" {
  source_lib
  fake_terminal t5 lab worker
  run has_labels t5 garden worker
  [ "$status" -ne 0 ]
}

@test "has_labels is false for another role" {
  source_lib
  fake_terminal t5 garden orchestrator
  run has_labels t5 garden worker
  [ "$status" -ne 0 ]
}

@test "has_labels is false when hc get fails" {
  source_lib
  run has_labels t7 garden worker
  [ "$status" -ne 0 ]
}

@test "has_labels is false for a finished terminal" {
  source_lib
  fake_terminal t5 garden worker
  jq '.state="finished"' "$FAKE_DIR/hc-get-t5.json" >"$FAKE_DIR/x" && mv "$FAKE_DIR/x" "$FAKE_DIR/hc-get-t5.json"
  run has_labels t5 garden worker
  [ "$status" -ne 0 ]
}

@test "hc_labels prints the labels of a live terminal" {
  source_lib
  fake_terminal t5 garden worker
  run hc_labels t5
  [ "$status" -eq 0 ]
  [ "$(jq -r '.board' <<<"$output")" = garden ]
}

@test "board_slug makes a short lowercase slug" {
  source_lib
  run board_slug "Fix the Login!"
  [ "$output" = fix-the-login ]
}

@test "new_uuid prints a lowercase UUID" {
  source_lib
  run new_uuid
  [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "new_uuid lowercases an uppercase uuidgen (macOS)" {
  source_lib
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho 0A1B2C3D-0000-4000-8000-ABCDEF012345\n' >"$BATS_TEST_TMPDIR/bin/uuidgen"
  chmod +x "$BATS_TEST_TMPDIR/bin/uuidgen"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run new_uuid
  [ "$output" = 0a1b2c3d-0000-4000-8000-abcdef012345 ]
}

@test "state_dir makes the state folder" {
  source_lib
  run state_dir
  [ "$output" = "$XDG_STATE_HOME/board-orchestrator-hc" ]
  [ -d "$output" ]
}

# --- Rex versions ---

# rex_block BOARD ROLE [claude|shell]: a live Rex block with a record.
rex_lib_block() {
  export REX_BIN="$BATS_TEST_DIRNAME/fake-rex" BOARD_REX_POLL=0
  export REX_BLOCK=block:00000000-0000-0000-0000-000000000001 REX_SESSION=session:fake-1
  mkdir -p "$FAKE_DIR/rex"
  RB=block:00000000-0000-0000-0000-000000000005
  fake_block session:fake-1 "$RB" window:fake-1 w "${3:-claude}"
  rex_record_file "$RB" "$(jq -cn --arg b "$1" --arg r "$2" \
    '{board:$b, role:$r, rex_session:"session:fake-1", window:"window:fake-1"}')"
  source_lib
}

@test "has_labels is true for a live terminal of that board and role (Rex)" {
  source_lib
  rex_lib_block garden worker
  run has_labels "$RB" garden worker
  [ "$status" -eq 0 ]
}

@test "has_labels is false for another board (Rex)" {
  source_lib
  rex_lib_block lab worker
  run has_labels "$RB" garden worker
  [ "$status" -ne 0 ]
}

@test "has_labels is false for another role (Rex)" {
  source_lib
  rex_lib_block garden orchestrator
  run has_labels "$RB" garden worker
  [ "$status" -ne 0 ]
}

@test "has_labels is false when rex get fails (Rex)" {
  source_lib
  rex_lib_block garden worker
  run has_labels block:00000000-0000-0000-0000-000000000006 garden worker
  [ "$status" -ne 0 ]
}

@test "has_labels is false for a closed block (Rex)" {
  source_lib
  rex_lib_block garden worker
  : >"$FAKE_DIR/rex/blocks.jsonl"
  run has_labels "$RB" garden worker
  [ "$status" -ne 0 ]
}

@test "hc_labels prints the labels of a live block (Rex)" {
  source_lib
  rex_lib_block garden worker
  run hc_labels "$RB"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.board' <<<"$output")" = garden ]
}
