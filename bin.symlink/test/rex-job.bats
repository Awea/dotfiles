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
  mkdir -p "$FAKE_DIR"
  : >"$FAKE_LOG"
}

# ended BLOCK CODE: the process of BLOCK ended with exit code CODE.
ended() {
  jq -c --argjson c "$2" '.last_exit.exit_code = $c' "$FIX/process-exited.json" >"$FAKE_DIR/rex/process-$1.json"
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
