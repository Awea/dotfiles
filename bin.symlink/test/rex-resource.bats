#!/usr/bin/env bats
# Tests of rex-resource, with the fake rex of the board-orchestrator tests.
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  RR="$BATS_TEST_DIRNAME/../rex-resource"
  # The folder of the scripts, as rex-resource finds it (readlink -f of its path).
  BIN=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)
  FAKE="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fake-rex"
  export REX_BIN="$FAKE"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake" FAKE_LOG="$BATS_TEST_TMPDIR/log"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export REX_RESOURCE_POLL=0.1 REX_RESOURCE_STALE=60
  # The Renux block of the caller. A test sets it: the env of the test run can have one.
  unset REX_BLOCK
  mkdir -p "$FAKE_DIR"
  : >"$FAKE_LOG"
  LOCK="$XDG_STATE_HOME/rex-resource/lock"
  FIX="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fixtures/rex"
  STATE="$XDG_STATE_HOME/rex-resource"
}

# live_block: print the ID of a new block of another session, a live caller.
live_block() {
  "$FAKE" new other --json | jq -r '.initial_windows[0].block_ids[0]'
}

# ends_on_wait BLOCK: the command of BLOCK ends at the next rex wait.
ends_on_wait() {
  printf '#!/bin/sh\ncp "%s" "%s"\n' "$FIX/process-exited.json" "$FAKE_DIR/rex/process-$1.json" \
    >"$FAKE_DIR/rex/on-wait"
  chmod +x "$FAKE_DIR/rex/on-wait"
}

@test "the first call makes the resources session and starts the resource" {
  run "$RR" shop-postgres /tmp/x -- postgres -D data
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  session=$(jq -r .session <<<"$output")
  grep -qF 'rex new resources' "$FAKE_LOG"
  # No REX_BLOCK: rex-starter gets an empty block and writes no record.
  grep -qF "rex run -s $session --focus=false --keep-open --interactive --label shop-postgres --cwd /tmp/x --json -- $BIN/rex-starter  postgres -D data" "$FAKE_LOG"
}

@test "a caller in Renux gives its block to rex-starter" {
  REX_BLOCK=$(live_block)
  export REX_BLOCK
  run "$RR" shop-postgres /tmp/x -- postgres -D data
  [ "$status" -eq 0 ]
  grep -qF -- "--json -- $BIN/rex-starter $REX_BLOCK postgres -D data" "$FAKE_LOG"
  [ "$(jq -c .argv <<<"$output")" = '["postgres","-D","data"]' ]
}

@test "a second call gives the same block and starts nothing" {
  run "$RR" shop-postgres /tmp/x -- postgres -D data
  first=$(jq -r .block <<<"$output")
  run "$RR" shop-postgres /tmp/x -- postgres -D data
  [ "$status" -eq 0 ]
  [ "$(jq -r .block <<<"$output")" = "$first" ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c '^rex new ' "$FAKE_LOG")" -eq 1 ]
}

@test "a closed resources session is made again" {
  run "$RR" shop-postgres /tmp/x -- postgres
  old=$(jq -r .session <<<"$output")
  "$FAKE" kill "$old"
  run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .session <<<"$output")" != "$old" ]
  [ "$(grep -c '^rex new ' "$FAKE_LOG")" -eq 2 ]
}

@test "a resource whose block is gone is started again" {
  run "$RR" shop-postgres /tmp/x -- postgres
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  "$FAKE" api call block.close "{\"session_id\":\"$session\",\"block_id\":\"$block\"}"
  run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .block <<<"$output")" != "$block" ]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 2 ]
}

@test "a stale lock is removed" {
  mkdir -p "$LOCK"
  touch -t "$(date -d '120 seconds ago' +%Y%m%d%H%M.%S 2>/dev/null || date -v-120S +%Y%m%d%H%M.%S)" "$LOCK"
  run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ ! -e "$LOCK" ]
}

@test "a young lock makes the call wait" {
  mkdir -p "$LOCK"
  (sleep 0.5; rmdir "$LOCK") &
  run "$RR" shop-postgres /tmp/x -- postgres
  wait
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
}

@test "no -- is a usage error" {
  run "$RR" shop-postgres /tmp/x postgres
  [ "$status" -eq 2 ]
}

@test "an empty name is a usage error" {
  run "$RR" "" /tmp/x -- postgres
  [ "$status" -eq 2 ]
}

@test "rex does not answer" {
  FAKE_REX_FAIL=1 run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 1 ]
  [[ "$output" == *"rex-resource: rex does not answer"* ]]
  [ ! -e "$LOCK" ]
}

@test "without REX_BIN the script runs the rex command of PATH" {
  mkdir -p "$BATS_TEST_TMPDIR/pathbin"
  ln -s "$FAKE" "$BATS_TEST_TMPDIR/pathbin/rex"
  unset REX_BIN
  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
}

@test "a found block gives the cwd and argv of its start" {
  mkdir -p "$BATS_TEST_TMPDIR/db"
  run "$RR" shop-postgres "$BATS_TEST_TMPDIR/db" -- postgres -D "my data"
  [ "$(jq -r .cwd <<<"$output")" = "$BATS_TEST_TMPDIR/db" ]
  [ "$(jq -c .argv <<<"$output")" = '["postgres","-D","my data"]' ]
  run "$RR" shop-postgres /tmp/other -- other
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -r .cwd <<<"$output")" = "$BATS_TEST_TMPDIR/db" ]
  [ "$(jq -c .argv <<<"$output")" = '["postgres","-D","my data"]' ]
}

@test "a found block without a saved start gives the cwd and program of its process" {
  run "$RR" shop-postgres /tmp/x -- postgres
  rm -f "$XDG_STATE_HOME/rex-resource/shop-postgres.json"
  run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -r .cwd <<<"$output")" = /home/user/.workspace/dotfiles ]
  [ "$(jq -c .argv <<<"$output")" = '["/home/user/.local/bin/claude"]' ]
}

@test "a resource whose process ended is closed and started again" {
  run "$RR" shop-postgres /tmp/x -- postgres
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  cp "$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fixtures/rex/process-exited.json" \
    "$FAKE_DIR/rex/process-$block.json"
  run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .block <<<"$output")" != "$block" ]
  [ "$(jq -r 'keys | join(",")' <<<"$output")" = argv,block,cwd,ended,exit_code,port,session,started ]
  grep -qF "rex block close -s $session $block" "$FAKE_LOG"
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 2 ]
}

@test "an ended resource that no live block uses closes at the next call" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- postgres
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  [ -f "$XDG_STATE_HOME/rex-resource/shop-postgres.users" ]
  cp "$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fixtures/rex/process-exited.json" \
    "$FAKE_DIR/rex/process-$block.json"
  REX_BLOCK=block:gone run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  grep -qF "rex block close -s $session $block" "$FAKE_LOG"
  [ ! -e "$XDG_STATE_HOME/rex-resource/shop-postgres.json" ]
}

@test "--sweep with --keep-ended or a name is a usage error" {
  run "$RR" --sweep --keep-ended
  [ "$status" -eq 2 ]
  run "$RR" --keep-ended --sweep
  [ "$status" -eq 2 ]
  run "$RR" --sweep shop-postgres /tmp/x -- postgres
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "the fake rex skips --interactive before a window label" {
  "$FAKE" new s >/dev/null
  session=$("$FAKE" api call session.list '{}' | jq -r '.sessions[0].session_id')
  "$FAKE" window new -s "$session" --interactive logs -- tail -f x >/dev/null
  [ "$("$FAKE" api call session.list_blocks "{\"session_id\":\"$session\"}" | jq -r '.blocks[1].label')" = logs ]
}

@test "a running resource that no live block uses gets one ctrl+c at the next calls" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  REX_BLOCK=block:gone run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  grep -qxF "rex send-key -s $session -b $block ctrl+c" "$FAKE_LOG"
  ! grep -q '^rex block close' "$FAKE_LOG"
  [ -f "$STATE/shop-postgres.json" ]
  [ -f "$STATE/shop-postgres.stop" ]
  run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  [ "$(grep -c '^rex send-key' "$FAKE_LOG")" -eq 1 ]
}

@test "a running resource stays while one of its caller blocks lives" {
  user=$(live_block)
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  REX_BLOCK=$user run "$RR" shop-postgres /tmp/x -- docker compose up db
  run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  ! grep -q '^rex send-key' "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.stop" ]
}

@test "a running resource with no caller in Renux stays, also when it is old" {
  run "$RR" shop-postgres /tmp/x -- docker compose up db
  [ "$(cat "$STATE/shop-postgres.users")" = outside ]
  touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null || date -v-2H +%Y%m%d%H%M.%S)" \
    "$STATE/shop-postgres.json"
  run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  ! grep -q '^rex send-key' "$FAKE_LOG"
}

@test "a running resource that a caller outside Renux shares stays when the Renux callers are gone" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  run "$RR" shop-postgres /tmp/x -- docker compose up db
  [ "$(sort "$STATE/shop-postgres.users" | tr '\n' ' ')" = "block:gone outside " ]
  run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  ! grep -q '^rex send-key' "$FAKE_LOG"
}

@test "an ended resource that a caller outside Renux shares closes when the Renux callers are gone" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- postgres
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  run "$RR" shop-postgres /tmp/x -- postgres
  cp "$FIX/process-exited.json" "$FAKE_DIR/rex/process-$block.json"
  run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  grep -qF "rex block close -s $session $block" "$FAKE_LOG"
}

@test "a failed ctrl+c marks nothing: the next call sends it again" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  FAKE_REX_KEY_FAIL=1 run "$RR" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/shop-postgres.stop" ]
  run "$RR" docs /tmp/x -- make docs
  [ "$(grep -c '^rex send-key' "$FAKE_LOG")" -eq 2 ]
  [ -f "$STATE/shop-postgres.stop" ]
}

@test "--sweep stops a running resource that no live block uses, waits for its end and closes it" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  ends_on_wait "$block"
  run "$RR" --sweep
  [ "$status" -eq 0 ]
  [ "$output" = shop-postgres ]
  grep -qxF "rex send-key -s $session -b $block ctrl+c" "$FAKE_LOG"
  grep -qxF "rex wait -s $session $block --for 20s --json" "$FAKE_LOG"
  grep -qxF "rex block close -s $session $block" "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.json" ]
  [ ! -e "$STATE/shop-postgres.users" ]
  [ ! -e "$STATE/shop-postgres.stop" ]
  [ ! -e "$LOCK" ]
}

@test "--sweep keeps a resource whose command still runs after the ctrl+c" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  run "$RR" --sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q '^rex block close' "$FAKE_LOG"
  [ -f "$STATE/shop-postgres.stop" ]
}

@test "a call for a stopping resource waits for its end and starts it again" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  run "$RR" docs /tmp/x -- make docs
  [ -f "$STATE/shop-postgres.stop" ]
  ends_on_wait "$block"
  REX_BLOCK=block:new run "$RR" shop-postgres /tmp/x -- docker compose up db
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .block <<<"$output")" != "$block" ]
  grep -qxF "rex wait -s $session $block --for 20s --json" "$FAKE_LOG"
  grep -qxF "rex block close -s $session $block" "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.stop" ]
  [ "$(cat "$STATE/shop-postgres.users")" = block:new ]
}

@test "a call for a stopping resource that still runs uses it" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  block=$(jq -r .block <<<"$output")
  run "$RR" docs /tmp/x -- make docs
  REX_BLOCK=block:new run "$RR" shop-postgres /tmp/x -- docker compose up db
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -r .block <<<"$output")" = "$block" ]
  grep -q '^rex wait ' "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.stop" ]
}

# bad_list ACTION: from now on, the calls of session.list after the first one do ACTION
# (exit 1, or a wrong answer), then the fake rex answers.
bad_list() {
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$*" = "--autostart=false api call session.list {}" ]; then' \
    "  n=\$(cat '$BATS_TEST_TMPDIR/n' 2>/dev/null || echo 0); echo \$((n + 1)) >'$BATS_TEST_TMPDIR/n'" \
    "  if [ \"\$n\" -ge 1 ]; then $1; fi" \
    'fi' \
    "exec '$FAKE' \"\$@\"" >"$BATS_TEST_TMPDIR/rex"
  chmod +x "$BATS_TEST_TMPDIR/rex"
  export REX_BIN="$BATS_TEST_TMPDIR/rex"
}

@test "a failed list of the live blocks stops nothing" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  bad_list 'exit 1'
  run "$RR" --sweep
  [ "$status" -eq 0 ]
  ! grep -q '^rex send-key' "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.stop" ]
}

@test "a wrong answer to the list of the live blocks stops nothing" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  bad_list "echo '{\"error\":\"x\"}'; exit 0"
  run "$RR" --sweep
  [ "$status" -eq 0 ]
  ! grep -q '^rex send-key' "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.stop" ]
}

@test "a wrong process answer stops nothing" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  printf '{"error":"x"}\n' >"$FAKE_DIR/rex/process-$(jq -r .block <<<"$output").json"
  run "$RR" --sweep
  [ "$status" -eq 0 ]
  ! grep -q '^rex send-key' "$FAKE_LOG"
  [ ! -e "$STATE/shop-postgres.stop" ]
}

@test "a call for a stopping resource waits without the lock" {
  REX_BLOCK=block:gone run "$RR" shop-postgres /tmp/x -- docker compose up db
  run "$RR" docs /tmp/x -- make docs
  printf '#!/bin/sh\n[ -e "%s" ] || touch "%s"\n' "$LOCK" "$BATS_TEST_TMPDIR/free" >"$FAKE_DIR/rex/on-wait"
  chmod +x "$FAKE_DIR/rex/on-wait"
  REX_BLOCK=block:new run "$RR" shop-postgres /tmp/x -- docker compose up db
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/free" ]
}

@test "--done without --keep-running is a usage error: a shared resource keeps its stop rule" {
  run "$RR" --done db
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "--port saves the port of the start and prints it in the JSON of each call" {
  run "$RR" --port 24931 shop-postgres /tmp/x -- postgres -p 24931
  [ "$status" -eq 0 ]
  [ "$(jq -c .port <<<"$output")" = 24931 ]
  [ "$(jq -r .port "$STATE/shop-postgres.json")" = 24931 ]
  run "$RR" shop-postgres /tmp/x -- postgres -p 24931
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -c .port <<<"$output")" = 24931 ]
}

@test "a call without --port prints a null port" {
  run "$RR" shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -c .port <<<"$output")" = null ]
}

@test "a found block without a saved port prints a null port" {
  run "$RR" shop-postgres /tmp/x -- postgres
  # A start that an older script saved: no port in it.
  printf '{"cwd":"/tmp/x","argv":["postgres"]}\n' >"$STATE/shop-postgres.json"
  run "$RR" --port 24931 shop-postgres /tmp/x -- postgres
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -c .port <<<"$output")" = null ]
}

@test "--port refuses a port that another name holds and starts nothing" {
  run "$RR" --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  [ "$status" -eq 0 ]
  run "$RR" --port 24931 shop-postgres-b /tmp/b -- postgres -p 24931
  [ "$status" -eq 3 ]
  [[ "$output" == *"rex-resource: port 24931 is held by shop-postgres-a"* ]]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 1 ]
  [ ! -e "$STATE/shop-postgres-b.json" ]
  [ ! -e "$LOCK" ]
}

@test "two names on two ports start two copies" {
  run "$RR" --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  a=$(jq -r .block <<<"$output")
  run "$RR" --port 24941 shop-postgres-b /tmp/b -- postgres -p 24941
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .block <<<"$output")" != "$a" ]
  [ "$(jq -c .port <<<"$output")" = 24941 ]
}

@test "the port of a gone block is free again" {
  run "$RR" --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  "$FAKE" api call block.close "{\"session_id\":\"$session\",\"block_id\":\"$block\"}"
  run "$RR" --port 24931 shop-postgres-b /tmp/b -- postgres -p 24931
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -c .port <<<"$output")" = 24931 ]
}

@test "a refused port keeps the ended block of the name" {
  run "$RR" --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  run "$RR" --port 24941 shop-postgres-b /tmp/b -- postgres -p 24941
  session=$(jq -r .session <<<"$output")
  block=$(jq -r .block <<<"$output")
  cp "$FIX/process-exited.json" "$FAKE_DIR/rex/process-$block.json"
  run "$RR" --port 24931 shop-postgres-b /tmp/b -- postgres -p 24931
  [ "$status" -eq 3 ]
  ! grep -qF "rex block close -s $session $block" "$FAKE_LOG"
}

@test "an ended block of the name starts again on the new port" {
  run "$RR" --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  block=$(jq -r .block <<<"$output")
  cp "$FIX/process-exited.json" "$FAKE_DIR/rex/process-$block.json"
  run "$RR" --port 24941 shop-postgres-a /tmp/a -- postgres -p 24941
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -c .port <<<"$output")" = 24941 ]
}

@test "a port that is not a number from 1 to 65535 is a usage error" {
  for p in "" abc 0 65536 12x -1; do
    run "$RR" --port "$p" shop-postgres /tmp/x -- postgres
    [ "$status" -eq 2 ]
  done
  run "$RR" --port
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "--port with --sweep or --done is a usage error" {
  run "$RR" --port 24931 --sweep
  [ "$status" -eq 2 ]
  run "$RR" --keep-running --port 24931 --done db
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "a port of another session is not refused" {
  run "$RR" --session other --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  # The state folder of the session "other" is in the folder of the resources.
  run "$RR" --port 24931 shop-postgres-b /tmp/b -- postgres -p 24931
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
}

@test "--keep-ended on an ended block of the name checks no port" {
  run "$RR" --port 24931 shop-postgres-a /tmp/a -- postgres -p 24931
  run "$RR" --port 24941 shop-postgres-b /tmp/b -- postgres -p 24941
  block=$(jq -r .block <<<"$output")
  cp "$FIX/process-exited.json" "$FAKE_DIR/rex/process-$block.json"
  run "$RR" --keep-ended --port 24931 shop-postgres-b /tmp/b -- postgres -p 24931
  [ "$status" -eq 0 ]
  [ "$(jq -r .ended <<<"$output")" = true ]
  [ "$(jq -c .port <<<"$output")" = 24941 ]
}
