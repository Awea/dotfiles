#!/usr/bin/env bats
# Tests of rex-job, with the fake rex of the board-orchestrator tests.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  RJ="$BATS_TEST_DIRNAME/../rex-job"
  FAKE="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fake-rex"
  FIX="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test/fixtures/rex"
  export REX_BIN="$FAKE"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake" FAKE_LOG="$BATS_TEST_TMPDIR/log"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export REX_RESOURCE_POLL=0.1 REX_RESOURCE_STALE=60
  # The Renux block of the caller. Each test sets it: the env of the test run can have one.
  unset REX_BLOCK
  JOBS="$XDG_STATE_HOME/rex-resource/jobs"
  mkdir -p "$FAKE_DIR"
  : >"$FAKE_LOG"
}

# ended BLOCK CODE: the process of BLOCK ended with exit code CODE.
ended() {
  jq -c --argjson c "$2" '.last_exit.exit_code = $c' "$FIX/process-exited.json" >"$FAKE_DIR/rex/process-$1.json"
}

# live_block: print the ID of a new block of another session, a live caller.
live_block() {
  "$FAKE" new other --json | jq -r '.initial_windows[0].block_ids[0]'
}

# old FILE: FILE changed 2 hours ago.
old() {
  touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null || date -v-2H +%Y%m%d%H%M.%S)" "$1"
}

@test "the first call makes the jobs session and starts the job" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .ended <<<"$output")" = false ]
  grep -qF 'rex new jobs' "$FAKE_LOG"
  session=$(jq -r .session <<<"$output")
  grep -qF "rex run -s $session --focus=false --keep-open --interactive --label deploy-web-4fb7f80 --cwd /tmp/x --json -- make deploy" "$FAKE_LOG"
}

@test "a second call on a live job gives the same block and starts nothing" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  first=$(jq -r .block <<<"$output")
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 0 ]
  [ "$(jq -r .block <<<"$output")" = "$first" ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -r .ended <<<"$output")" = false ]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 1 ]
}

@test "an ended job stays: the same block, its exit code, and no new start" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  first=$(jq -r .block <<<"$output")
  ended "$first" 2
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 0 ]
  [ "$(jq -r .block <<<"$output")" = "$first" ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(jq -r .ended <<<"$output")" = true ]
  [ "$(jq -r .exit_code <<<"$output")" = 2 ]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 1 ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "--again closes an ended job and starts it again" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  first=$(jq -r .block <<<"$output")
  ended "$first" 1
  run "$RJ" --again deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(jq -r .block <<<"$output")" != "$first" ]
  grep -q '^rex block close' "$FAKE_LOG"
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 2 ]
}

@test "--again on a live job starts nothing" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  first=$(jq -r .block <<<"$output")
  run "$RJ" --again deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 0 ]
  [ "$(jq -r .block <<<"$output")" = "$first" ]
  [ "$(jq -r .started <<<"$output")" = false ]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 1 ]
}

@test "a job and a resource with the same name do not mix" {
  run "$RJ" docs /tmp/x -- make docs
  job=$(jq -r .block <<<"$output")
  run "$BATS_TEST_DIRNAME/../rex-resource" docs /tmp/x -- make docs
  [ "$status" -eq 0 ]
  [ "$(jq -r .block <<<"$output")" != "$job" ]
  grep -qF 'rex new resources' "$FAKE_LOG"
}

@test "a usage error exits 2" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x make deploy
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "an ended job closes at the next call when its caller block is gone" {
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  session=$(jq -r .session <<<"$output")
  first=$(jq -r .block <<<"$output")
  [ "$(cat "$JOBS/deploy-web-4fb7f80.users")" = block:gone ]
  ended "$first" 0
  run "$RJ" build-api-1234567 /tmp/x -- make build
  [ "$status" -eq 0 ]
  [ "$(jq -r .started <<<"$output")" = true ]
  grep -qF "rex block close -s $session $first" "$FAKE_LOG"
  [ ! -e "$JOBS/deploy-web-4fb7f80.json" ]
  [ ! -e "$JOBS/deploy-web-4fb7f80.users" ]
}

@test "an ended job stays while one of its caller blocks lives" {
  user=$(live_block)
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  first=$(jq -r .block <<<"$output")
  REX_BLOCK=$user run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$(jq -r .block <<<"$output")" = "$first" ]
  [ "$(wc -l <"$JOBS/deploy-web-4fb7f80.users")" -eq 2 ]
  ended "$first" 0
  run "$RJ" build-api-1234567 /tmp/x -- make build
  [ "$status" -eq 0 ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "a job whose command runs stays, also with no live caller" {
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  run "$RJ" build-api-1234567 /tmp/x -- make build
  [ "$status" -eq 0 ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "an ended job with no caller block stays until its start is 1 hour old" {
  run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  session=$(jq -r .session <<<"$output")
  first=$(jq -r .block <<<"$output")
  [ ! -e "$JOBS/deploy-web-4fb7f80.users" ]
  ended "$first" 0
  run "$RJ" build-api-1234567 /tmp/x -- make build
  ! grep -q '^rex block close' "$FAKE_LOG"
  old "$JOBS/deploy-web-4fb7f80.json"
  run "$RJ" build-api-1234567 /tmp/x -- make build
  [ "$status" -eq 0 ]
  grep -qF "rex block close -s $session $first" "$FAKE_LOG"
}

@test "a call never closes the job that it asks for" {
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  first=$(jq -r .block <<<"$output")
  ended "$first" 3
  REX_BLOCK=block:gone2 run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 0 ]
  [ "$(jq -r .block <<<"$output")" = "$first" ]
  [ "$(jq -r .exit_code <<<"$output")" = 3 ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "a job started again has only its new caller" {
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  ended "$(jq -r .block <<<"$output")" 1
  REX_BLOCK=block:new run "$RJ" --again deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$(jq -r .started <<<"$output")" = true ]
  [ "$(cat "$JOBS/deploy-web-4fb7f80.users")" = block:new ]
}

@test "--sweep closes the ended jobs with no live caller, prints their names and starts nothing" {
  user=$(live_block)
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  done_job=$(jq -r .block <<<"$output")
  REX_BLOCK=block:gone run "$RJ" build-api-1234567 /tmp/x -- make build
  REX_BLOCK=$user run "$RJ" test-api-1234567 /tmp/x -- make test
  kept=$(jq -r .block <<<"$output")
  ended "$done_job" 0
  ended "$kept" 0
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  [ "$output" = deploy-web-4fb7f80 ]
  [ "$(grep -c '^rex block close' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c '^rex run ' "$FAKE_LOG")" -eq 3 ]
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

@test "a failed list of the live blocks closes nothing" {
  user=$(live_block)
  REX_BLOCK=$user run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  ended "$(jq -r .block <<<"$output")" 0
  bad_list 'exit 1'
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "a wrong answer to the list of the live blocks closes nothing" {
  user=$(live_block)
  REX_BLOCK=$user run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  ended "$(jq -r .block <<<"$output")" 0
  bad_list "echo '{\"error\":\"x\"}'; exit 0"
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "a wrong process answer closes nothing" {
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  printf '{"error":"x"}\n' >"$FAKE_DIR/rex/process-$(jq -r .block <<<"$output").json"
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  ! grep -q '^rex block close' "$FAKE_LOG"
}

@test "--sweep closes a job whose name has a slash" {
  REX_BLOCK=block:gone run "$RJ" deploy/web /tmp/x -- make deploy
  [ -f "$JOBS/deploy_web.users" ]
  ended "$(jq -r .block <<<"$output")" 0
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  [ "$output" = deploy/web ]
  [ ! -e "$JOBS/deploy_web.json" ]
}

@test "--sweep removes the saved start of a job whose block is gone" {
  REX_BLOCK=block:gone run "$RJ" deploy-web-4fb7f80 /tmp/x -- make deploy
  session=$(jq -r .session <<<"$output")
  "$FAKE" api call block.close "{\"session_id\":\"$session\",\"block_id\":\"$(jq -r .block <<<"$output")\"}"
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  [ ! -e "$JOBS/deploy-web-4fb7f80.json" ]
  [ ! -e "$JOBS/deploy-web-4fb7f80.users" ]
}

@test "--sweep with no jobs session makes nothing" {
  run "$RJ" --sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q '^rex new' "$FAKE_LOG"
}

@test "--sweep with a job name is a usage error" {
  run "$RJ" --sweep deploy-web-4fb7f80 /tmp/x -- make deploy
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}
