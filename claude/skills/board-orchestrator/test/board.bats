#!/usr/bin/env bats
# board.sh: boards, running, open, stop.

bats_require_minimum_version 1.5.0
load helper

setup() {
  rex_setup
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  for b in lab home "my board"; do
    printf -- '---\nkanban-plugin: board\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/$b.md"
  done
  printf 'just a note\n' >"$OBSIDIAN_VAULT_PATH/Boards/notes.md"
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$STATE"
}

board() { run bash "$SKILL_DIR/board.sh" "$@"; }

# record_orchestrator BOARD ADDR: the orchestrator record of BOARD.
record_orchestrator() { printf '%s\t%s\n' "$2" "$1" >"$STATE/orchestrator-$(board_slug_of "$1")"; }
board_slug_of() { tr '[:upper:] ' '[:lower:]-' <<<"$1"; }

# line_of PATTERN: the line number of the first logged call that matches PATTERN.
line_of() { grep -n -E -m 1 -- "$1" "$FAKE_LOG" | cut -d: -f1; }

@test "boards lists only kanban boards, by name" {
  board boards
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | [.key, .board]]' <<<"$output")" = '[["1","home"],["2","lab"],["3","my board"]]' ]
}

@test "open refuses a board that does not exist" {
  board open nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no board nope"* ]]
  [ -z "$(calls 'space.new')" ]
}

@test "stop with no orchestrator exits 1" {
  board stop home
  [ "$status" -eq 1 ]
  [[ "$output" == *"no orchestrator"* ]]
  [ -z "$(calls 'space.close')" ]
}

@test "board.sh has no notification call" {
  ! grep -n -E 'notify|notification|playSound|toast' "$SKILL_DIR/board.sh"
}

RX=block:00000000-0000-0000-0000-000000000009

# rex_mode: the caller is the popup of a Renux client, on the fake Rex.
rex_mode() {
  export REX_BIN="$BATS_TEST_DIRNAME/fake-rex" BOARD_REX_POLL=0
  export REX_BLOCK=block:00000000-0000-0000-0000-000000000001 REX_SESSION=session:fake-0 REX_CLIENT=client:c1
  mkdir -p "$FAKE_DIR/rex"
}

# rex_term BOARD claude|shell [TYPED]: the live orchestrator block $RX of BOARD, with its record.
rex_term() {
  fake_block session:fake-1 "$RX" window:fake-1 orchestrator "$2"
  rex_record_file "$RX" "$(jq -cn --arg b "$1" --arg t "${3:-}" \
    '{board:$b, role:"orchestrator", rex_session:"session:fake-1", window:"window:fake-1"}
     + (if $t == "" then {} else {typed:$t} end)')"
  record_orchestrator "$1" "$RX"
}

@test "running lists the boards with a live orchestrator (Rex)" {
  rex_mode
  rex_term home claude
  record_orchestrator lab block:00000000-0000-0000-0000-000000000008
  board running
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '["home"]' ]
}

@test "open ignores a record of another board (Rex)" {
  rex_mode
  rex_term lab claude
  record_orchestrator home "$RX"
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex new home orchestrator')" ]
}

@test "open finds a board that has many boards after it (Rex)" {
  rex_mode
  for i in $(seq 1 200); do
    printf -- '---\nkanban-plugin: board\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/zz-$i.md"
  done
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex new home orchestrator')" ]
}

@test "restart types nothing when claude runs in the orchestrator terminal (Rex)" {
  rex_mode
  rex_term home claude
  board restart home "$RX"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
}

@test "restart types nothing when the command went into the same shell a moment ago (Rex)" {
  rex_mode
  rex_term home shell "929020 $(date +%s)"
  board restart home "$RX"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
}

@test "restart exits 3 for a terminal that is not the orchestrator of the board (Rex)" {
  rex_mode
  rex_term home shell
  board restart home block:00000000-0000-0000-0000-000000000007
  [ "$status" -eq 3 ]
  board restart lab "$RX"
  [ "$status" -eq 3 ]
  rm "$STATE/orchestrator-home"
  board restart home "$RX"
  [ "$status" -eq 3 ]
  [ -z "$(calls '^rex send ')" ]
}

@test "open only shows the shell when restart typed the command there a moment ago (Rex)" {
  rex_mode
  rex_term home shell "929020 $(date +%s)"
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls 'do session.select')" ]
  [ -z "$(calls '^rex send ')" ]
}

@test "open starts claude again in a shell that got the command long ago, or in another shell (Rex)" {
  rex_mode
  rex_term home shell "929020 $(($(date +%s) - 120))"
  board open home
  [ -n "$(calls '^rex send ')" ]
  : >"$FAKE_LOG"
  rex_term home shell "299 $(date +%s)"
  board open home
  [ -n "$(calls '^rex send ')" ]
  [[ "$(jq -r .typed "$STATE/rex/$RX.json")" == 929020\ * ]]
}
