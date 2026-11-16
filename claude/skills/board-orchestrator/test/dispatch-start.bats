#!/usr/bin/env bats
# dispatch.sh start: a worker claude as an hc child of the orchestrator.

bats_require_minimum_version 1.5.0
load helper

setup() {
  hc_setup
  REPO="$BATS_TEST_TMPDIR/repo"
  repo_with_push_policy "$REPO"
  printf 'Fix the login bug.\n' >"$BATS_TEST_TMPDIR/p.md"
}

start() { run bash "$SKILL_DIR/dispatch.sh" start "${1:-task}" "$REPO" "Fix login" "$BATS_TEST_TMPDIR/p.md"; }

@test "start refuses outside hc" {
  start
  [ "$status" -eq 2 ]
  [[ "$output" == *HC_TERMINAL_ID* ]]
  [ -z "$(calls '^hc run')" ]
}

@test "start refuses when the caller is not an orchestrator" {
  export HC_TERMINAL_ID=t5
  fake_terminal t5 garden worker
  start
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a board orchestrator"* ]]
  [ -z "$(calls '^hc run')" ]
}

@test "start ignores the Herdr 0.9.5 environment" {
  orchestrator t5 garden
  export HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1
  start
  [ "$status" -eq 0 ]
  [ -z "$(calls '^herdr ')" ]
}

@test "start runs claude as an hc child with the board labels" {
  orchestrator t5 garden
  start
  [ "$status" -eq 0 ]
  run_args
  has_arg --bg
  [ "$(arg_after --name)" = fix-login ]
  [ "$(arg_after --cwd)" = "$REPO" ]
  has_arg board=garden
  has_arg board.role=worker
  session=$(arg_after --session-id)
  [[ "$session" =~ ^[0-9a-f-]{36}$ ]]
  has_arg "board.session=$session"
  [ "$(arg_after -n)" = fix-login ]
  [ "$(arg_after --)" = claude ]
}

@test "start puts -- before the prompt, after --allowedTools" {
  orchestrator t5 garden
  mkdir -p "$REPO/.claude"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  [ "$status" -eq 0 ]
  run_args
  n=${#RUN_ARGS[@]}
  [ "${RUN_ARGS[$((n - 2))]}" = -- ]
  [[ "${RUN_ARGS[$((n - 1))]}" == "Fix the login bug."* ]]
  has_arg --allowedTools
}

@test "start footer tells the worker how to report" {
  orchestrator t5 garden
  start
  run_args
  prompt=${RUN_ARGS[-1]}
  report=$(sed -n 2p <<<"$output")
  [[ "$prompt" == *"After you write the report, run: hc send t5 \"report fix-login $report\""* ]]
  [[ "$prompt" != *"view tab"* ]]
  [[ "$prompt" != *"ctrl+b"* ]]
  [[ "$prompt" != *"hidden Herdr session"* ]]
}

@test "start footer tells the worker to show no vault change text in its conversation" {
  orchestrator t5 garden
  start
  run_args
  [[ "${RUN_ARGS[-1]}" == *"give the note path and the exact old and new text only in the report. Do not show them in the conversation"* ]]
}

@test "start footer tells a task worker how to close" {
  orchestrator t5 garden
  start
  run_args
  [[ "${RUN_ARGS[-1]}" == *"When the user tells you to close, run: hc send t5 \"close fix-login\""* ]]
}

@test "start footer gives an auto worker no close line" {
  orchestrator t5 garden
  mkdir -p "$REPO/.claude"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  run_args
  [[ "${RUN_ARGS[-1]}" != *"When the user tells you to close"* ]]
}

@test "start footer lets a task worker start agents for an independent review" {
  orchestrator t5 garden
  start
  run_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"You can start subagents and other claude terminals"*"independent review"* ]]
  [[ "$prompt" != *"Do not start other agents"* ]]
  [[ "$prompt" == *"Do not change the herdr-app window."* ]]
}

@test "start footer tells a task worker how to share a long job with other workers" {
  orchestrator t5 garden
  start
  run_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"hc run --bg --no-notify --outlive-parent --name <job>"* ]]
  [[ "$prompt" == *"name_taken"* ]]
  [[ "$prompt" == *"hc wait <job>"* ]]
  [[ "$prompt" == *"Do not hc rm or hc kill a shared job"* ]]
}

@test "start footer gives an automatic worker no shared job rule" {
  orchestrator t5 garden
  mkdir -p "$REPO/.claude"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  [ "$status" -eq 0 ]
  run_args
  [[ "${RUN_ARGS[-1]}" != *"--outlive-parent"* ]]
}

@test "start auto mode adds the read-only flags" {
  orchestrator t5 garden
  mkdir -p "$REPO/.claude"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  [ "$status" -eq 0 ]
  run_args
  has_arg --setting-sources
  [ "$(arg_after --permission-mode)" = dontAsk ]
  [[ "${RUN_ARGS[-1]}" == *"Bash(make test)"* ]]
  [[ "${RUN_ARGS[-1]}" != *"You can start subagents"* ]]
}

@test "start records the worker" {
  orchestrator t5 garden
  start
  run_args
  session=$(arg_after --session-id)
  report=$(sed -n 2p <<<"$output")
  line=$(cat "$XDG_STATE_HOME/board-orchestrator-hc/workers")
  [ "$line" = "$(printf 't9\ttask\tgarden\t%s\t%s\t%s\tfix-login' "$report" "$session" "$REPO")" ]
}

@test "start adds a suffix when the name is in use" {
  orchestrator t5 garden
  printf '{"terminals":[{"address":"t3","name":"fix-login","state":"live"}]}\n' >"$FAKE_DIR/hc-ls.json"
  start
  run_args
  [ "$(arg_after --name)" = fix-login-2 ]
}

@test "start prints the address and the report" {
  orchestrator t5 garden
  start
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p <<<"$output")" = t9 ]
  [[ "$(sed -n 2p <<<"$output")" == "$XDG_STATE_HOME/board-orchestrator-hc/fix-login-"*.md ]]
}

@test "start task runs with a deny push policy" {
  orchestrator t5 garden
  printf '{"permissions":{"deny":["Bash(git push*)"]}}\n' >"$REPO/.claude/settings.local.json"
  start
  [ "$status" -eq 0 ]
}

@test "start task exits 2 with no push policy" {
  orchestrator t5 garden
  rm "$REPO/.claude/settings.local.json"
  start
  [ "$status" -eq 2 ]
  [[ "$output" == *"no push policy"* ]]
  [ -z "$(calls '^hc run')" ]
}

@test "start allows the worker to send its report to the orchestrator" {
  orchestrator t5 garden
  start
  run_args
  has_arg 'Bash(hc send t5 *)'
}

@test "start auto mode allows the report send and lists it" {
  orchestrator t5 garden
  mkdir -p "$REPO/.claude"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  run_args
  has_arg 'Bash(hc send t5 *)'
  [[ "${RUN_ARGS[-1]}" == *$'\n''Bash(hc send t5 *)'* ]]
}
