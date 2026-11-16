#!/usr/bin/env bats
# board.sh: boards, running, open, stop.

bats_require_minimum_version 1.5.0
load helper

setup() {
  hc_setup
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

@test "running lists the boards with a live orchestrator" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator
  record_orchestrator lab t6
  board running
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '["home"]' ]
}

@test "open focuses a running orchestrator" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator claude
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^herdr-app do agent.focus --terminal t5')" ]
  [ -z "$(calls 'space.new')" ]
  [ -z "$(calls '^hc send')" ]
}

@test "open restarts claude in a shell after a reboot" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator zsh
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^herdr-app do pane.focus --terminal t5')" ]
  [ -z "$(calls 'agent.focus')" ]
  [ -n "$(calls '^hc send t5 claude --effort high --autocompact 200k -n home-orchestrator -- /board-orchestrator\\ home')" ]
  [ -z "$(calls 'space.new')" ]
}

@test "open makes the space before claude starts" {
  printf '{"space":"sp1","tab":"tb1","terminal":"t7"}\n' >"$FAKE_DIR/app-do.json"
  board open home
  [ "$status" -eq 0 ]
  new=$(line_of "^herdr-app do space.new --name home orchestrator --folder $OBSIDIAN_VAULT_PATH --tab orchestrator")
  label=$(line_of '^hc label t7 board=home board.role=orchestrator')
  send=$(line_of '^hc send t7 claude ')
  [ -n "$new" ] && [ -n "$label" ] && [ -n "$send" ]
  [ "$new" -lt "$label" ]
  [ "$label" -lt "$send" ]
  [ "$(cat "$STATE/orchestrator-home")" = "$(printf 't7\thome')" ]
}

@test "open ignores a record of another board" {
  record_orchestrator home t5
  fake_terminal t5 lab orchestrator claude
  printf '{"space":"sp1","tab":"tb1","terminal":"t7"}\n' >"$FAKE_DIR/app-do.json"
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls 'space.new')" ]
  [ -z "$(calls 'agent.focus')" ]
}

@test "open works for a board with a space" {
  printf '{"space":"sp1","tab":"tb1","terminal":"t7"}\n' >"$FAKE_DIR/app-do.json"
  board open "my board"
  [ "$status" -eq 0 ]
  [ -n "$(calls '^herdr-app do space.new --name my board orchestrator ')" ]
  [ -n "$(calls '^hc label t7 board=my board board.role=orchestrator')" ]
  [ -n "$(calls '^hc send t7 claude .* -n my-board-orchestrator -- /board-orchestrator\\ my\\ board')" ]
  [ -f "$STATE/orchestrator-my-board" ]
}

@test "open fails fast when hc is down" {
  export FAKE_HC_FAIL=1
  start=$(date +%s)
  board open home
  [ "$status" -eq 1 ]
  [ $(($(date +%s) - start)) -le 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"hc does not answer"* ]]
  [ -z "$(calls 'space.new')" ]
}

@test "open refuses a board that does not exist" {
  board open nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no board nope"* ]]
  [ -z "$(calls 'space.new')" ]
}

@test "stop closes the space and keeps the worker records" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator claude '{"herdr.space":"sp9"}'
  record_worker t9 home s1
  board stop home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^herdr-app do space.close --id sp9 --confirmed true')" ]
  [ ! -f "$STATE/orchestrator-home" ]
  [ -s "$STATE/workers" ]
}

@test "stop with no orchestrator exits 1" {
  board stop home
  [ "$status" -eq 1 ]
  [[ "$output" == *"no orchestrator"* ]]
  [ -z "$(calls 'space.close')" ]
}

@test "open runs no Herdr 0.9.5 call" {
  export HERDR_ENV=1 HERDR_WORKSPACE_ID=w1
  printf '{"space":"sp1","tab":"tb1","terminal":"t7"}\n' >"$FAKE_DIR/app-do.json"
  board open home
  [ "$status" -eq 0 ]
  [ -z "$(calls '^herdr ')" ]
}

@test "board.sh has no notification call" {
  ! grep -n -E 'notify|notification|playSound|toast' "$SKILL_DIR/board.sh"
}

@test "open finds a board that has many boards after it" {
  for i in $(seq 1 200); do
    printf -- '---\nkanban-plugin: board\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/zz-$i.md"
  done
  printf '{"space":"sp1","tab":"tb1","terminal":"t7"}\n' >"$FAKE_DIR/app-do.json"
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls 'space.new')" ]
}
