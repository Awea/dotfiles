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

@test "running in herdr-app does not list a board that runs in Renux" {
  export REX_BIN="$BATS_TEST_DIRNAME/fake-rex"
  mkdir -p "$FAKE_DIR/rex"
  b=block:00000000-0000-0000-0000-000000000009
  fake_block session:fake-1 "$b" window:fake-1 orchestrator claude
  rex_record_file "$b" '{"board":"home","role":"orchestrator","rex_session":"session:fake-1","window":"window:fake-1"}'
  record_orchestrator home "$b"
  board running
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '[]' ]
  board running all
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

@test "stop kills a terminal that has no herdr.space label" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator claude
  board stop home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^hc kill t5')" ]
  [ -z "$(calls 'space.close')" ]
  [ ! -f "$STATE/orchestrator-home" ]
}

@test "stop exits 1 when herdr-app does not close the space" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator claude '{"herdr.space":"sp9"}'
  export FAKE_APP_FAIL=1
  board stop home
  [ "$status" -eq 1 ]
  [[ "$output" == *"herdr-app did not close the space"* ]]
  [ -f "$STATE/orchestrator-home" ]
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

# shell_terminal ADDR BOARD FOREGROUND [TYPED]: the orchestrator terminal ADDR of BOARD, a
# shell of pid 300 with FOREGROUND in front, and the board.typed label TYPED.
shell_terminal() {
  local f="$FAKE_DIR/hc-get-$1.json"
  fake_terminal "$1" "$2" orchestrator "$3"
  jq --arg t "${4:-}" '.pid = 300 | .foreground.pid = (if .foreground.name == "claude" then 512 else 300 end)
    | if $t == "" then . else .labels["board.typed"] = $t end' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

@test "restart starts claude in the shell of the orchestrator, with no focus" {
  record_orchestrator "my board" t5
  shell_terminal t5 "my board" zsh
  board restart "my board" t5
  [ "$status" -eq 0 ]
  label=$(line_of '^hc label t5 board.typed=300 [0-9]+$')
  send=$(line_of '^hc send t5 claude --effort high --autocompact 200k -n my-board-orchestrator -- /board-orchestrator\\ my\\ board$')
  [ -n "$label" ] && [ -n "$send" ]
  [ "$label" -lt "$send" ]
  [ -z "$(calls '^herdr-app')" ]
}

@test "restart types nothing when claude runs in the orchestrator terminal" {
  record_orchestrator home t5
  shell_terminal t5 home claude
  board restart home t5
  [ "$status" -eq 0 ]
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "restart types nothing when the command went into the same shell a moment ago" {
  record_orchestrator home t5
  shell_terminal t5 home zsh "300 $(date +%s)"
  board restart home t5
  [ "$status" -eq 0 ]
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "restart exits 3 for a terminal that is not the orchestrator of the board" {
  record_orchestrator home t5
  shell_terminal t5 home zsh
  shell_terminal t6 home zsh
  board restart home t6
  [ "$status" -eq 3 ]
  [[ "$output" == *"t6 is not the orchestrator of the board home"* ]]
  board restart lab t5
  [ "$status" -eq 3 ]
  rm "$STATE/orchestrator-home"
  board restart home t5
  [ "$status" -eq 3 ]
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "open only shows the shell when restart typed the command there a moment ago" {
  record_orchestrator home t5
  shell_terminal t5 home zsh "300 $(date +%s)"
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^herdr-app do pane.focus --terminal t5')" ]
  [ -z "$(calls '^hc send')" ]
}

@test "open starts claude again in a shell that got the command long ago, or in another shell" {
  record_orchestrator home t5
  shell_terminal t5 home zsh "300 $(($(date +%s) - 120))"
  board open home
  [ -n "$(calls '^hc send t5 claude ')" ]
  : >"$FAKE_LOG"
  shell_terminal t5 home zsh "299 $(date +%s)"
  board open home
  [ -n "$(calls '^hc label t5 board.typed=300 ')" ]
  [ -n "$(calls '^hc send t5 claude ')" ]
}

# --- Rex versions of the tests above ---

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
