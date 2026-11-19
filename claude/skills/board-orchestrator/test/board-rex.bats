#!/usr/bin/env bats
# board.sh in Renux: open, stop, restart, running, and the guard between the two backends.

bats_require_minimum_version 1.5.0
load helper

O=block:00000000-0000-0000-0000-000000000009

setup() {
  rex_setup
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  for b in home "my board"; do
    printf -- '---\nkanban-plugin: board\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/$b.md"
  done
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$STATE"
  # The caller is the popup of a Renux client.
  export REX_BLOCK=block:00000000-0000-0000-0000-000000000001 REX_SESSION=session:fake-0 REX_CLIENT=client:c1
}

board() { run bash "$SKILL_DIR/board.sh" "$@"; }

# rex_args CMD [N]: the arguments of the Nth saved call, one for each element of RUN_ARGS.
rex_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-$1-${2:-1}.args"; }

line_of() { grep -n -E -m 1 -- "$1" "$FAKE_LOG" | cut -d: -f1; }

# record_orchestrator BOARD ADDR: the orchestrator record of BOARD.
record_orchestrator() { printf '%s\t%s\n' "$2" "$1" >"$STATE/orchestrator-$(tr '[:upper:] ' '[:lower:]-' <<<"$1")"; }

# rex_orch BOARD [claude|shell]: a live Renux orchestrator block $O, with its record.
rex_orch() {
  fake_block session:fake-1 "$O" window:fake-1 orchestrator "${2:-claude}"
  rex_record_file "$O" "$(jq -cn --arg b "$1" \
    '{board:$b, role:"orchestrator", rex_session:"session:fake-1", window:"window:fake-1"}')"
  record_orchestrator "$1" "$O"
}

@test "open on Rex makes the session first, then types claude" {
  board open "my board"
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex new my board orchestrator --window orchestrator')" ]
  [ "$(line_of '^rex new ')" -lt "$(line_of '^rex send ')" ]
  [ -n "$(calls '^rex -C client:c1 do session.select')" ]
  [ "$(line_of 'do session.select')" -lt "$(line_of '^rex send ')" ]
  rex_args send
  [ "${RUN_ARGS[4]}" = 'BOARD=my\ board BOARD_ROLE=orchestrator claude --effort high --autocompact 200k -n my-board-orchestrator -- /board-orchestrator\ my\ board' ]
  [ "$(cut -f1 "$STATE/orchestrator-my-board")" = "block:00000000-0000-0000-0000-000000000001" ]
  [ "$(cut -f2 "$STATE/orchestrator-my-board")" = "my board" ]
}

@test "open on Rex shows a live orchestrator and types nothing" {
  rex_orch home claude
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex -C client:c1 do session.select')" ]
  [ -z "$(calls '^rex new ')" ]
  [ -z "$(calls '^rex send ')" ]
}

@test "open on Rex types claude in a shell after a restart" {
  rex_orch home shell
  board open home
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex new ')" ]
  rex_args send
  [ "${RUN_ARGS[3]}" = "$O" ]
  [[ "${RUN_ARGS[4]}" == "BOARD=home BOARD_ROLE=orchestrator claude --effort high"* ]]
  [[ "$(jq -r .typed "$STATE/rex/$O.json")" =~ ^[0-9]+\ [0-9]+$ ]]
}

@test "open on Rex refuses a board that runs in herdr-app" {
  record_orchestrator home t5
  fake_terminal t5 home orchestrator claude
  board open home
  [ "$status" -eq 1 ]
  [[ "$output" == *"board.sh: home runs in herdr-app. Stop it there first."* ]]
  [ -z "$(calls '^rex new ')" ]
}

@test "open in herdr-app refuses a board that runs in Renux" {
  rex_orch home claude
  unset REX_BLOCK REX_SESSION REX_CLIENT
  export HC_TERMINAL_ID=t1
  board open home
  [ "$status" -eq 1 ]
  [[ "$output" == *"board.sh: home runs in Renux. Stop it there first."* ]]
  [ -z "$(calls 'space.new')" ]
}

@test "open on Rex starts again when the old session is gone" {
  record_orchestrator home "$O"
  rex_record_file "$O" '{"board":"home","role":"orchestrator","rex_session":"session:fake-1","window":"window:fake-1"}'
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex new home orchestrator')" ]
}

@test "open on Rex ignores an hc record when hc does not answer" {
  export FAKE_HC_FAIL=1
  record_orchestrator home t5
  fake_terminal t5 home orchestrator claude
  board open home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex new home orchestrator')" ]
}

@test "stop on Rex kills the session and keeps the worker records" {
  rex_orch home claude
  rex_worker block:00000000-0000-0000-0000-000000000008 home s1
  board stop home
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex kill session:fake-1')" ]
  [ ! -f "$STATE/orchestrator-home" ]
  [ ! -f "$STATE/rex/$O.json" ]
  [ -s "$STATE/workers" ]
}

@test "stop on Rex with no orchestrator exits 1" {
  board stop home
  [ "$status" -eq 1 ]
  [[ "$output" == *"no orchestrator"* ]]
}

@test "restart on Rex types claude in the recorded orchestrator" {
  rex_orch home shell
  board restart home "$O"
  [ "$status" -eq 0 ]
  rex_args send
  [ "${RUN_ARGS[3]}" = "$O" ]
  [[ "${RUN_ARGS[4]}" == "BOARD=home BOARD_ROLE=orchestrator claude --effort high"* ]]
  [ -z "$(calls '^rex -C ')" ]
}

@test "restart exits 3 for another block" {
  rex_orch home shell
  board restart home block:00000000-0000-0000-0000-000000000007
  [ "$status" -eq 3 ]
  [ -z "$(calls '^rex send ')" ]
}

@test "running in Renux lists only the boards of Renux, running all lists both backends" {
  rex_orch home claude
  record_orchestrator "my board" t5
  fake_terminal t5 "my board" orchestrator claude
  board running
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '["home"]' ]
  board running all
  [ "$status" -eq 0 ]
  [ "$(jq -c 'sort' <<<"$output")" = '["home","my board"]' ]
}

@test "running in Renux does not list a board that runs in herdr-app" {
  record_orchestrator "my board" t5
  fake_terminal t5 "my board" orchestrator claude
  board running
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '[]' ]
}

@test "stop on Rex removes the records before the kill ends the popup" {
  rex_orch home claude
  # ctrl+b X in the board session: the kill closes the popup, and board.sh gets SIGHUP.
  export FAKE_REX_KILL_HUP=1
  board stop home
  [ -n "$(calls '^rex kill session:fake-1')" ]
  [ ! -f "$STATE/orchestrator-home" ]
  [ ! -f "$STATE/rex/$O.json" ]
}

@test "stop on Rex keeps the records when the kill fails" {
  rex_orch home claude
  export FAKE_REX_KILL_FAIL=1
  board stop home
  [ "$status" -eq 1 ]
  [[ "$output" == *"Renux did not close the session"* ]]
  [ -f "$STATE/orchestrator-home" ]
  [ "$(jq -r .role "$STATE/rex/$O.json")" = orchestrator ]
  # The next open shows the same orchestrator: it starts no second one.
  : >"$FAKE_LOG"
  board open home
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex new ')" ]
}

@test "open on Rex sees a live watcher that runs with --autostart=false" {
  fake_spawners
  rex_orch home claude
  mkdir -p "$STATE/rex"
  bash -c 'exec -a "rex --autostart=false do -s session:fake-1 /x/board-watch.lua" sleep 30' &
  pid=$!
  printf '%s\n' "$pid" >"$STATE/rex/watch-session:fake-1.pid"
  board open home
  kill "$pid"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_DIR/spawn.log" ]
}

@test "open on Rex names Renux, not herdr-app or hc, when the session does not open" {
  cat >"$BATS_TEST_TMPDIR/rex-no-new" <<EOS
#!/usr/bin/env bash
a=("\$@"); [ "\${a[0]:-}" != --autostart=false ] || a=("\${a[@]:1}")
[ "\${a[0]:-}" != new ] || exit 1
exec "$SKILL_DIR/test/fake-rex" "\$@"
EOS
  chmod +x "$BATS_TEST_TMPDIR/rex-no-new"
  export REX_BIN="$BATS_TEST_TMPDIR/rex-no-new"
  board open home
  [ "$status" -eq 1 ]
  [[ "$output" == *"Renux did not open the session"* ]]
  [[ "$output" != *herdr-app* && "$output" != *"hc "* ]]
}

@test "open on Rex names rex when typing claude fails" {
  rex_orch home shell
  cat >"$BATS_TEST_TMPDIR/rex-no-send" <<EOS
#!/usr/bin/env bash
a=("\$@"); [ "\${a[0]:-}" != --autostart=false ] || a=("\${a[@]:1}")
[ "\${a[0]:-}" != send ] || exit 1
exec "$SKILL_DIR/test/fake-rex" "\$@"
EOS
  chmod +x "$BATS_TEST_TMPDIR/rex-no-send"
  export REX_BIN="$BATS_TEST_TMPDIR/rex-no-send"
  board open home
  [ "$status" -eq 1 ]
  [[ "$output" == *"rex did not start claude in $O"* ]]
}

# fake_spawners: setsid and nohup that log their arguments and start nothing. lib.sh puts
# $HOME/.local/bin first in PATH, so they go there.
fake_spawners() {
  mkdir -p "$HOME/.local/bin"
  for p in setsid nohup; do
    printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >>"$FAKE_DIR/spawn.log"\n' "$p" >"$HOME/.local/bin/$p"
    chmod +x "$HOME/.local/bin/$p"
  done
}

@test "open on Rex starts the watcher once" {
  fake_spawners
  board open "my board"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_DIR/spawn.log")" -eq 1 ]
  grep -Eq 'do -s session:[^ ]+ .*board-watch.lua dispatch=.*dispatch.sh session=session:' "$FAKE_DIR/spawn.log"
  # A live watcher: the pid file names a process that runs "rex do ... board-watch.lua".
  session=$(sed -E 's/.* do -s ([^ ]+) .*/\1/' "$FAKE_DIR/spawn.log")
  bash -c 'exec -a "rex do -s $0 /x/board-watch.lua" sleep 30' "$session" &
  pid=$!
  printf '%s\n' "$pid" >"$STATE/rex/watch-$session.pid"
  : >"$FAKE_DIR/spawn.log"
  board open "my board"
  kill "$pid"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_DIR/spawn.log" ]
}

@test "open on Rex starts the watcher again when the pid is a watcher of another session" {
  fake_spawners
  rex_orch home claude
  mkdir -p "$STATE/rex"
  bash -c 'exec -a "rex do -s session:other /x/board-watch.lua" sleep 30' &
  pid=$!
  printf '%s\n' "$pid" >"$STATE/rex/watch-session:fake-1.pid"
  board open home
  kill "$pid"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_DIR/spawn.log")" -eq 1 ]
}

@test "open on Rex starts the watcher again when the pid is not a watcher" {
  fake_spawners
  rex_orch home claude
  mkdir -p "$STATE/rex"
  sleep 30 &
  pid=$!
  printf '%s\n' "$pid" >"$STATE/rex/watch-session:fake-1.pid"
  board open home
  kill "$pid"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_DIR/spawn.log")" -eq 1 ]
}

@test "restart on Rex starts the watcher" {
  fake_spawners
  rex_orch home shell
  board restart home "$O"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_DIR/spawn.log")" -eq 1 ]
}
