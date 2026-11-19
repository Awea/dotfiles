#!/usr/bin/env bats
# Tests of rex-resource, with the fake rex of the board-orchestrator tests.
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  RR="$BATS_TEST_DIRNAME/../rex-resource"
  FAKE="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fake-rex"
  export REX_BIN="$FAKE"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake" FAKE_LOG="$BATS_TEST_TMPDIR/log"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export REX_RESOURCE_POLL=0.1 REX_RESOURCE_STALE=60
  mkdir -p "$FAKE_DIR"
  : >"$FAKE_LOG"
  LOCK="$XDG_STATE_HOME/rex-resource/lock"
}

@test "the first call makes the resources session and starts the resource" {
  run "$RR" shop-postgres /tmp/x -- postgres -D data
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  session=$(jq -r .session <<<"$output")
  grep -qF 'rex new resources' "$FAKE_LOG"
  grep -qF "rex run -s $session --focus=false --keep-open --interactive --label shop-postgres --cwd /tmp/x --json -- postgres -D data" "$FAKE_LOG"
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
  [ "$(jq -r 'keys | join(",")' <<<"$output")" = argv,block,cwd,session,started ]
  grep -qF "rex block close -s $session $block" "$FAKE_LOG"
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 2 ]
}

@test "the fake rex skips --interactive before a window label" {
  "$FAKE" new s >/dev/null
  session=$("$FAKE" api call session.list '{}' | jq -r '.sessions[0].session_id')
  "$FAKE" window new -s "$session" --interactive logs -- tail -f x >/dev/null
  [ "$("$FAKE" api call session.list_blocks "{\"session_id\":\"$session\"}" | jq -r '.blocks[1].label')" = logs ]
}
