#!/usr/bin/env bats
# dispatch.sh start: a worker claude as a window of the orchestrator session.

bats_require_minimum_version 1.5.0
load helper

setup() {
  rex_setup
  REPO="$BATS_TEST_TMPDIR/repo"
  repo_with_push_policy "$REPO"
  printf 'Fix the login bug.\n' >"$BATS_TEST_TMPDIR/p.md"
}

start() { run bash "$SKILL_DIR/dispatch.sh" start "${1:-task}" "$REPO" "Fix login" "$BATS_TEST_TMPDIR/p.md"; }

# alpha_board: REPO goes under the root of a test board alpha, with board MCP servers,
# allow rules and a notebooks folder.
alpha_board() {
  export BOARD_RESOURCES_HOME="$BATS_TEST_TMPDIR/board-resources"
  mkdir -p "$BOARD_RESOURCES_HOME/alpha" "$BATS_TEST_TMPDIR/ws/alpha"
  printf '%s\n' "$BATS_TEST_TMPDIR/ws/alpha" >"$BOARD_RESOURCES_HOME/alpha/roots"
  printf '%s\n' "$BATS_TEST_TMPDIR/ws/alpha/notebooks" >"$BOARD_RESOURCES_HOME/alpha/notebooks"
  printf '{"mcpServers":{}}\n' >"$BOARD_RESOURCES_HOME/alpha/mcp.json"
  printf '{"permissions":{"allow":["Bash(board-ro *)","mcp__appsignal"],"deny":["Bash(pass show beta/*)"]}}\n' \
    >"$BOARD_RESOURCES_HOME/alpha/settings.json"
  REPO="$BATS_TEST_TMPDIR/ws/alpha/repo"
  repo_with_push_policy "$REPO"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
}

# Rex versions of the tests above.

RO=block:01a1ef15-4833-735e-9530-226d79648a16
TELL_RULE() { printf 'Bash(%s/.claude/skills/board-orchestrator/dispatch.sh tell *)' "$HOME"; }

# rex_start_setup: the Rex setup, on top of the setup of this file.
rex_start_setup() {
  rex_setup
  mkdir -p "$XDG_STATE_HOME/board-orchestrator-hc"
}

auto_policy() {
  mkdir -p "$REPO/.claude"
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
}

# wn_args [N]: the arguments of the Nth rex window new call, in RUN_ARGS.
wn_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-window-new-${1:-1}.args"; }

@test "start runs claude in a Rex window with the board env (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  [ "$status" -eq 0 ]
  wn_args
  has_arg --focus=false
  [ "$(arg_after --cwd)" = "$REPO" ]
  has_arg BOARD=garden
  has_arg BOARD_ROLE=worker
  has_arg BOARD_NAME=fix-login
  session=$(arg_after --session-id)
  [[ "$session" =~ ^[0-9a-f-]{36}$ ]]
  has_arg "BOARD_SESSION=$session"
  [ "$(arg_after -n)" = fix-login ]
  [ "$(arg_after --)" = env ]
  [ "$(arg_after BOARD_RESOURCES_OFF=1)" = claude ]
}

@test "start puts -- before the prompt, after --allowedTools (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  [ "$status" -eq 0 ]
  wn_args
  n=${#RUN_ARGS[@]}
  [ "${RUN_ARGS[$((n - 2))]}" = -- ]
  [[ "${RUN_ARGS[$((n - 1))]}" == "Fix the login bug."* ]]
  has_arg --allowedTools
}

@test "start footer tells the worker how to report (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  prompt=${RUN_ARGS[-1]}
  report=$(sed -n 2p <<<"$output")
  [[ "$prompt" == *"After you write the report, run: $HOME/.claude/skills/board-orchestrator/dispatch.sh tell \"report fix-login $report\""* ]]
  [[ "$prompt" != *"view tab"* ]]
  [[ "$prompt" != *"ctrl+b"* ]]
  [[ "$prompt" != *"hidden Herdr session"* ]]
}

@test "start footer tells the worker to show no vault change text in its conversation (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  [[ "${RUN_ARGS[-1]}" == *"give the note path and the exact old and new text only in the report. Do not show them in the conversation"* ]]
}

@test "start footer tells the worker how to write a move of its own card (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  [[ "${RUN_ARGS[-1]}" == *"For a move of your own card, write only the target column, and the new context line when the user gives one."* ]]
}

@test "start footer tells a task worker how to close (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  [[ "${RUN_ARGS[-1]}" == *"When the user tells you to close, run: $HOME/.claude/skills/board-orchestrator/dispatch.sh tell \"close fix-login\""* ]]
}

@test "start footer gives an auto worker no close line (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  wn_args
  [[ "${RUN_ARGS[-1]}" != *"When the user tells you to close"* ]]
}

@test "start footer lets a task worker start agents for an independent review (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"You can start subagents and other claude terminals"*"independent review"* ]]
  [[ "$prompt" != *"Do not start other agents"* ]]
  [[ "$prompt" == *"Do not change the Renux window."* ]]
}

@test "start footer gives an automatic worker no shared job rule (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  [ "$status" -eq 0 ]
  wn_args
  [[ "${RUN_ARGS[-1]}" != *"--outlive-parent"* ]]
  [[ "${RUN_ARGS[-1]}" != *"Run a long job"* ]]
}

@test "start footer gives a task worker the order of the sources of truth (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  [ "$status" -eq 0 ]
  wn_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"most trusted first: 1. The words of the user"*"2. The live issue and PR"*"3. The code and git, after git fetch"*"4. The vault task note"*"5. The card"* ]]
  [[ "$prompt" == *"ask the user and do not choose"*"the code wins on the state and the issue wins on the goal"* ]]
}

@test "start footer gives an automatic worker no order of the sources of truth (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  [ "$status" -eq 0 ]
  wn_args
  [[ "${RUN_ARGS[-1]}" != *"most trusted first"* ]]
}

@test "start auto mode adds the read-only flags (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  [ "$status" -eq 0 ]
  wn_args
  has_arg --setting-sources
  [ "$(arg_after --permission-mode)" = dontAsk ]
  [[ "${RUN_ARGS[-1]}" == *"Bash(make test)"* ]]
  [[ "${RUN_ARGS[-1]}" != *"You can start subagents"* ]]
}

@test "start auto lets the worker read its prompt file after a compact (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  [ "$status" -eq 0 ]
  wn_args
  session=$(arg_after --session-id)
  has_arg "Read(/$XDG_STATE_HOME/board-orchestrator-hc/prompts/$session.md)"
}

@test "start records the worker (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  session=$(arg_after --session-id)
  new=$(sed -n 1p <<<"$output")
  report=$(sed -n 2p <<<"$output")
  line=$(cat "$XDG_STATE_HOME/board-orchestrator-hc/workers")
  [ "$line" = "$(printf '%s\ttask\tgarden\t%s\t%s\t%s\tfix-login' "$new" "$report" "$session" "$REPO")" ]
}

@test "start keeps the full prompt in a file of the session, for a compact (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  [ "$status" -eq 0 ]
  wn_args
  session=$(arg_after --session-id)
  f="$XDG_STATE_HOME/board-orchestrator-hc/prompts/$session.md"
  [ -f "$f" ]
  [ "$(cat "$f")" = "${RUN_ARGS[-1]}" ]
  [[ "$(cat "$f")" == "Fix the login bug."*"When you finish, write your report to"* ]]
}

@test "start removes the prompt file when the worker does not start (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  export FAKE_REX_WINDOW_FAIL=1
  start
  [ "$status" -eq 1 ]
  [ -f "$FAKE_DIR/rex/rex-window-new-1.args" ]
  [ -z "$(ls -A "$XDG_STATE_HOME/board-orchestrator-hc/prompts" 2>/dev/null)" ]
}

@test "start prints the block and the report (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  [ "$status" -eq 0 ]
  [[ "$(sed -n 1p <<<"$output")" == block:* ]]
  [[ "$(sed -n 2p <<<"$output")" == "$XDG_STATE_HOME/board-orchestrator-hc/fix-login-"*.md ]]
}

@test "start task runs with a deny push policy (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  printf '{"permissions":{"deny":["Bash(git push*)"]}}\n' >"$REPO/.claude/settings.local.json"
  start
  [ "$status" -eq 0 ]
}

@test "start task tells the worker the push policy of its repo (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  [[ "${RUN_ARGS[-1]}" == *"The push policy of your card repo is allow. Each push policy: allow,"* ]]
  [[ "${RUN_ARGS[-1]}" == *"give the branch in the report. A push rule in the CLAUDE.md of the repo comes first."* ]]
  printf '{"env":{"BOARD_PUSH_POLICY":"branch"}}\n' >"$REPO/.claude/settings.local.json"
  start
  wn_args 2
  [[ "${RUN_ARGS[-1]}" == *"The push policy of your card repo is branch."* ]]
  [[ "${RUN_ARGS[-1]}" == *"Claude asks the user for the first push of a branch, and later pushes to that branch have no question"* ]]
}

@test "start auto tells the worker no push policy (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  wn_args
  [[ "${RUN_ARGS[-1]}" != *"push policy"* ]]
}

@test "start task exits 2 with no push policy (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  rm "$REPO/.claude/settings.local.json"
  start
  [ "$status" -eq 2 ]
  [[ "$output" == *"no push policy"* ]]
  [ ! -e "$FAKE_DIR/rex/rex-window-new-1.args" ]
}

@test "start allows the worker to send its report to the orchestrator (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  start
  wn_args
  has_arg "$(TELL_RULE)"
}

@test "start auto mode allows the report send and lists it (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  auto_policy
  start auto
  wn_args
  has_arg "$(TELL_RULE)"
  [[ "${RUN_ARGS[-1]}" == *$'\n'"$(TELL_RULE)"* ]]
}

@test "start gives a task worker in a board folder the board MCP and rules (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" alpha
  alpha_board
  start
  [ "$status" -eq 0 ]
  wn_args
  [ "$(arg_after --mcp-config)" = "$BOARD_RESOURCES_HOME/alpha/mcp.json" ]
  settings=$(arg_after --settings)
  jq -e '.permissions.allow == ["Bash(board-ro *)","mcp__appsignal"]' <<<"$settings"
  jq -e '.permissions.deny == ["Bash(pass show beta/*)"]' <<<"$settings"
  jq -e '.enabledPlugins["obsidian-second-brain@obsidian-second-brain"] == false' <<<"$settings"
}

@test "start auto mode adds the board rules to the repo readonly rules (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" alpha
  alpha_board
  start auto
  [ "$status" -eq 0 ]
  wn_args
  jq -e '.permissions.allow == ["Bash(make test)","Bash(board-ro *)","mcp__appsignal"]' <<<"$(arg_after --settings)"
  [[ "${RUN_ARGS[-1]}" == *"Bash(board-ro *)"* ]]
}

@test "start auto mode keeps the repo .mcp.json and adds the board one (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" alpha
  alpha_board
  printf '{"mcpServers":{}}\n' >"$REPO/.mcp.json"
  start auto
  wn_args
  [ "$(arg_after --mcp-config)" = "$REPO/.mcp.json" ]
  [ "$(arg_after "$REPO/.mcp.json")" = "$BOARD_RESOURCES_HOME/alpha/mcp.json" ]
}

@test "start gives a worker outside a board no board flags (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" garden
  alpha_board
  REPO="$BATS_TEST_TMPDIR/other"
  repo_with_push_policy "$REPO"
  start
  [ "$status" -eq 0 ]
  wn_args
  ! has_arg --mcp-config
  ! jq -e '.permissions' <<<"$(arg_after --settings)"
  [[ "${RUN_ARGS[-1]}" != *"notebooks"* ]]
}

@test "start runs the worker claude with BOARD_RESOURCES_OFF=1 (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" alpha
  alpha_board
  start
  wn_args
  [ "$(arg_after --)" = env ]
  [ "$(arg_after BOARD_RESOURCES_OFF=1)" = claude ]
}

@test "start tells the worker the notebooks folder of its board (Rex)" {
  rex_start_setup
  rex_orchestrator "$RO" alpha
  alpha_board
  start
  wn_args
  [[ "${RUN_ARGS[-1]}" == *"You can also write and commit a notebook in $BATS_TEST_TMPDIR/ws/alpha/notebooks"* ]]
  [[ "${RUN_ARGS[-1]}" == *"board-ro list"* ]]
}
