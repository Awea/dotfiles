#!/usr/bin/env bats
# hooks/guard.sh and hooks/compact.sh in a Renux pane (REX_BLOCK set).

bats_require_minimum_version 1.5.0
load helper

setup() { rex_setup; }

guard() {
  local json
  json=$(jq -cn --arg c "$1" --arg d "${2:-${REPO:-$BATS_TEST_TMPDIR}}" --arg s "${3:-s1}" \
    '{session_id: $s, cwd: $d, tool_name: "Bash", tool_input: {command: $c}}')
  run bash "$SKILL_DIR/hooks/guard.sh" <<<"$json"
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$output"; }

rex_worker() { export REX_BLOCK=b1 REX_SESSION=rs1 BOARD=garden BOARD_ROLE=worker BOARD_NAME=w1; }

blocked() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"board-orchestrator: a board worker cannot $1. Write it in the report: the orchestrator does it."* ]]
}

@test "guard blocks rex window new for a Rex worker" {
  rex_worker
  guard 'rex window new'
  blocked 'change the Renux window (rex window)'
}

@test "guard blocks rex do for a Rex worker" {
  rex_worker
  guard 'cd /tmp && rex do x'
  blocked 'change the Renux window (rex do)'
}

@test "guard blocks rex api call session.focus_block for a Rex worker" {
  rex_worker
  guard 'rex api call session.focus_block {}'
  blocked 'change the Renux window (rex api call session.focus_block)'
}

@test "guard blocks a prefixed full path rex kill for a Rex worker" {
  rex_worker
  guard 'FOO=1 /usr/bin/rex kill s'
  blocked 'change the Renux window (rex kill)'
}

@test "guard blocks rex server stop but allows rex server status" {
  rex_worker
  guard 'rex server stop'
  blocked 'change the Renux window (rex server stop)'
  guard 'rex server status'
  [ "$status" -eq 0 ]
}

@test "guard allows rex capture and rex api call session.view for a Rex worker" {
  rex_worker
  guard 'rex capture b1'
  [ "$status" -eq 0 ]
  guard 'rex api call session.view {}'
  [ "$status" -eq 0 ]
  guard 'rex --help'
  [ "$status" -eq 0 ]
}

@test "guard lets a Rex worker wait for a shared job, and still blocks rex run and rex block close" {
  rex_worker
  guard 'rex wait block:01a1 --for 3600s --json'
  [ "$status" -eq 0 ]
  guard 'rex run -s s1 --label x -- make'
  blocked 'change the Renux window (rex run)'
  guard 'rex block close -s s1 block:01a1'
  blocked 'change the Renux window (rex block)'
}

@test "guard allows grep rex file" {
  rex_worker
  guard 'grep rex file'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does nothing for a Rex orchestrator" {
  export REX_BLOCK=b1 BOARD=garden BOARD_ROLE=orchestrator
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does nothing for a Rex pane with no BOARD_ROLE" {
  export REX_BLOCK=b1
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the push rules apply to a Rex worker" {
  rex_worker
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  ORIGIN="$BATS_TEST_TMPDIR/origin.git" REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/master
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b master
  git -C "$REPO" commit -q --allow-empty -m one
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin master
  git -C "$REPO" remote set-head origin master
  mkdir -p "$REPO/.claude"
  printf '{"env":{"BOARD_PUSH_POLICY":"branch"}}\n' >"$REPO/.claude/settings.local.json"
  git -C "$REPO" checkout -q -b feat
  git -C "$REPO" commit -q --allow-empty -m two
  guard 'git push -u origin HEAD'
  [ "$status" -eq 0 ]
  [ "$(decision)" = ask ]
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" == *"first push of the branch feat"* ]]
}

@test "compact tells a Rex orchestrator to read the skill again" {
  export REX_BLOCK=b1 BOARD="my board" BOARD_ROLE=orchestrator
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *'"my board"'* ]]
}

@test "compact is silent for a Rex worker" {
  rex_worker
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard finds rex inside a command" {
  rex_worker
  local c
  for c in 'id=$(rex window new)' 'for b in x y; do rex kill $b; done' 'if rex kill s; then :; fi' \
    '(rex kill s)' 'echo `rex kill s`' 'time rex kill s' 'xargs rex kill' 'env X=1 "rex" kill s'; do
    guard "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "guard names a bare rex with no trailing space" {
  rex_worker
  guard 'rex'
  blocked 'change the Renux window (rex)'
}

@test "guard does nothing for a Rex worker pane with no BOARD" {
  export REX_BLOCK=b1 BOARD_ROLE=worker
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does nothing for a non-board pane" {
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
