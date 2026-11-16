#!/usr/bin/env bats
# hooks/guard.sh (PreToolUse Bash) and hooks/compact.sh (SessionStart compact).

bats_require_minimum_version 1.5.0
load helper

guard() {
  local json
  json=$(jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}')
  run bash "$SKILL_DIR/hooks/guard.sh" <<<"$json"
}

compact() { run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'; }

as_worker() { export HC_TERMINAL_ID=t9; fake_terminal t9 garden worker; }

@test "guard is silent outside hc" {
  export HERDR_ENV=1 HERDR_WORKSPACE_ID=w1
  guard 'hc run --bg -- claude "do it"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$FAKE_LOG" ]
}

@test "guard allows an agent start in a worker, for an independent review" {
  as_worker
  printf '{"templates":[{"name":"reviewer"}]}\n' >"$FAKE_DIR/hc-templates.json"
  for c in 'hc run --bg --name x -- claude "review the branch"' 'hc run codex' 'hc run --bg pi' \
    'cd /x && hc run --bg reviewer "review x"' 'hc run --bg --name y -- /usr/bin/claude'; do
    guard "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c"; return 1; }
  done
}

@test "guard blocks window changes in a worker" {
  as_worker
  guard 'herdr-app do tab.new --name x'
  [ "$status" -eq 2 ]
  [[ "$output" == *herdr-app* ]]
}

@test "guard allows a slow command in a worker" {
  as_worker
  guard 'hc run --bg --no-notify --name t --cwd /repo -- make test'
  [ "$status" -eq 0 ]
  guard 'hc wait t --timeout 110'
  [ "$status" -eq 0 ]
}

@test "guard allows the shared long job of the worker prompt" {
  as_worker
  guard 'hc run --bg --no-notify --outlive-parent --name deploy-web-4fb7f80 --cwd /repo -- bin/wait-deploy 4fb7f80'
  [ "$status" -eq 0 ]
  guard 'hc get deploy-web-4fb7f80 && hc wait deploy-web-4fb7f80 --timeout 3600'
  [ "$status" -eq 0 ]
}

@test "guard allows everything in the orchestrator" {
  export HC_TERMINAL_ID=t5
  fake_terminal t5 garden orchestrator
  guard 'hc run --bg -- claude "x"'
  [ "$status" -eq 0 ]
}

@test "guard allows a terminal that is not on a board" {
  export HC_TERMINAL_ID=t3
  guard 'hc run --bg -- claude "x"'
  [ "$status" -eq 0 ]
}

@test "compact speaks only for an orchestrator" {
  export HC_TERMINAL_ID=t5
  fake_terminal t5 garden orchestrator
  compact
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = SessionStart ]
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$output")
  [[ "$ctx" == *"~/.claude/skills/board-orchestrator/SKILL.md"* ]]
  [[ "$ctx" == *"orchestrator of the board garden"* ]]
}

@test "compact is silent for a worker and outside hc" {
  as_worker
  compact
  [ -z "$output" ]
  unset HC_TERMINAL_ID
  export HERDR_ENV=1
  compact
  [ -z "$output" ]
}

@test "compact gives the whole board name as the arguments" {
  export HC_TERMINAL_ID=t5
  fake_terminal t5 "my board" orchestrator
  compact
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$output")
  [[ "$ctx" == *'with "my board" as the whole argument text'* ]]
}
