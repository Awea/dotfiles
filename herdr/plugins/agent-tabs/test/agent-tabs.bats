#!/usr/bin/env bats
# Tests for the agent-tabs plugin scripts. A fake herdr records each call.

setup() {
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HERDR_BIN_PATH="$BATS_TEST_DIRNAME/fake-herdr"
  export FAKE_LOG="$BATS_TEST_TMPDIR/herdr.log"
  export HERDR_WORKSPACE_ID="w1"
  export HERDR_PANE_ID="w1:p1"
  export HERDR_PLUGIN_ID="awea.agent-tabs"
  export HOME="$BATS_TEST_TMPDIR/home"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export HERDR_PLUGIN_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export AGENT_TABS_LAUNCHER="$BATS_TEST_DIRNAME/fake-systemd-run"
  export AGENT_TABS_TITLE_TIMEOUT=0
  mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"
  touch "$HERDR_PLUGIN_CONFIG_DIR/debug"
  : >"$FAKE_LOG"
}

# Run the bash code $1 in a terminal. Type each next argument (a printf format) after
# a pause, so that the code is ready to read it. Set status to the exit code of the
# code, and output to the terminal output.
run_in_tty() {
  export TTY_CODE="$1"
  shift
  run script -qec 'bash -c "$TTY_CODE"' /dev/null < <(
    for keys in "$@"; do
      sleep 0.3
      printf "$keys"
    done
    sleep 0.5
  )
}

@test "notify writes only to the log when debug is off" {
  rm "$HERDR_PLUGIN_CONFIG_DIR/debug"
  unset HERDR_PANE_ID
  run bash "$PLUGIN_DIR/new-agent-tab.sh" open
  [ "$status" -eq 1 ]
  [[ "$output" == "agent-tabs: No pane has focus."* ]]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "new-tab open opens the prompt popup" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" open
  [ "$status" -eq 0 ]
  grep -qx 'plugin | pane | open | --plugin | awea.agent-tabs | --entrypoint | new-tab-prompt | --env | AGENT_TABS_PANE=w1:p1 | --env | AGENT_TABS_WORKSPACE=w1' "$FAKE_LOG"
}

@test "new-tab open shows a notification when no pane has focus" {
  unset HERDR_PANE_ID
  run bash "$PLUGIN_DIR/new-agent-tab.sh" open
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs | --body | ' "$FAKE_LOG"
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "new-tab worker opens a background tab and sends the prompt" {
  export FAKE_CWD="/work/project"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'fix "auth" & $HOME'
  [ "$status" -eq 0 ]
  grep -qx 'pane | get | w1:p1' "$FAKE_LOG"
  grep -qx 'tab | create | --workspace | w1 | --cwd | /work/project | --no-focus' "$FAKE_LOG"
  grep -qx 'agent | start | claude | --kind | claude | --pane | w1:p9 | --timeout | 60000' "$FAKE_LOG"
  grep -qx 'agent | rename | w1:p9 | --clear' "$FAKE_LOG"
  grep -qx 'agent | prompt | w1:p9 | fix "auth" & $HOME' "$FAKE_LOG"
}

@test "new-tab worker without prompt opens a clean background tab" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $HOME | --no-focus" "$FAKE_LOG"
  grep -qx 'agent | start | claude | --kind | claude | --pane | w1:p9 | --timeout | 60000' "$FAKE_LOG"
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "new-tab worker clears the temporary agent name when claude does not start" {
  export FAKE_START_FAIL=1
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello'
  [ "$status" -eq 1 ]
  grep -qx 'agent | rename | w1:p9 | --clear' "$FAKE_LOG"
}

@test "new-tab worker shows a notification when claude does not start" {
  export FAKE_START_FAIL=1
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello'
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs | --body | ' "$FAKE_LOG"
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "new-tab worker shows a notification when the prompt fails" {
  export FAKE_FINAL_PROMPT_FAIL=1
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello'
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs | --body | ' "$FAKE_LOG"
}

@test "handoff open shows a notification when the pane has no agent" {
  run bash "$PLUGIN_DIR/handoff.sh" open
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs' "$FAKE_LOG"
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "handoff open shows a notification for an agent that is not claude" {
  export FAKE_AGENT_KIND="codex"
  run bash "$PLUGIN_DIR/handoff.sh" open
  [ "$status" -eq 1 ]
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "handoff open shows a notification when claude is working" {
  export FAKE_AGENT_KIND="claude" FAKE_AGENT_STATUS="working"
  run bash "$PLUGIN_DIR/handoff.sh" open
  [ "$status" -eq 1 ]
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "handoff open opens the popup for an idle claude" {
  export FAKE_AGENT_KIND="claude" FAKE_AGENT_STATUS="done"
  run bash "$PLUGIN_DIR/handoff.sh" open
  [ "$status" -eq 0 ]
  grep -qx 'plugin | pane | open | --plugin | awea.agent-tabs | --entrypoint | handoff-prompt | --env | AGENT_TABS_PANE=w1:p1 | --env | AGENT_TABS_WORKSPACE=w1' "$FAKE_LOG"
}

@test "handoff worker sends the focus and opens a handoff tab" {
  export FAKE_CWD="/work/project" FAKE_WRITE_DOC=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 'fix "auth" & $HOME'
  [ "$status" -eq 0 ]
  local doc_re="$TMPDIR/herdr-handoff-[0-9]{8}-[0-9]{6}-[0-9]+\\.md"
  grep -qE '^agent \| prompt \| w1:p1 \| /handoff fix "auth" & \$HOME\. Save the handoff document to '"$doc_re"' \| --wait \| --until \| idle \| --until \| done \| --timeout \| 900000$' "$FAKE_LOG"
  grep -qx 'tab | create | --workspace | w1 | --cwd | /work/project | --no-focus' "$FAKE_LOG"
  grep -qx 'agent | start | claude | --kind | claude | --pane | w1:p9 | --timeout | 60000' "$FAKE_LOG"
  grep -qx 'agent | rename | w1:p9 | --clear' "$FAKE_LOG"
  grep -qE '^agent \| prompt \| w1:p9 \| Read the handoff document at '"$doc_re"', then continue the work\.$' "$FAKE_LOG"
}

@test "handoff worker without focus sends a plain /handoff" {
  export FAKE_WRITE_DOC=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qE '^agent \| prompt \| w1:p1 \| /handoff Save the handoff document to '"$TMPDIR"'/herdr-handoff-' "$FAKE_LOG"
}

@test "handoff worker stops when the agent does not write the document" {
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs' "$FAKE_LOG"
  [ "$(grep -c '^tab | create' "$FAKE_LOG")" -eq 0 ]
}

@test "handoff worker stops when the /handoff wait fails" {
  export FAKE_WRITE_DOC=1 FAKE_PROMPT_FAIL=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs' "$FAKE_LOG"
  [ "$(grep -c '^tab | create' "$FAKE_LOG")" -eq 0 ]
}

@test "handoff worker shows the document path when claude does not start" {
  export FAKE_WRITE_DOC=1 FAKE_START_FAIL=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 1 ]
  grep -qE '^notification \| show \| Agent tabs \| --body \| .*/herdr-handoff-[0-9-]+\.md' "$FAKE_LOG"
  [ "$(grep -c '^agent | prompt | w1:p9' "$FAKE_LOG")" -eq 0 ]
}

@test "handoff worker shows the document path when the last prompt fails" {
  export FAKE_WRITE_DOC=1 FAKE_FINAL_PROMPT_FAIL=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 1 ]
  grep -qE '^notification \| show \| Agent tabs \| --body \| .*/herdr-handoff-[0-9-]+\.md' "$FAKE_LOG"
}

@test "read_effort maps each key to a level" {
  for pair in l:low m:medium h:high x:xhigh M:max; do
    run bash -c 'source "$1/lib.sh"; read_effort 2>/dev/null' _ "$PLUGIN_DIR" <<<"${pair%%:*}"
    [ "$status" -eq 0 ]
    [ "$output" = "${pair#*:}" ]
  done
}

@test "read_effort prints nothing for Enter and at end of input" {
  run bash -c 'source "$1/lib.sh"; read_effort 2>/dev/null' _ "$PLUGIN_DIR" <<<""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'source "$1/lib.sh"; read_effort 2>/dev/null' _ "$PLUGIN_DIR" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "read_effort asks again after an incorrect key" {
  run bash -c 'source "$1/lib.sh"; read_effort 2>/dev/null' _ "$PLUGIN_DIR" <<<"zh"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "new-tab worker starts claude with the effort" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello' high
  [ "$status" -eq 0 ]
  grep -qx 'agent | start | claude | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | high' "$FAKE_LOG"
}

@test "new-tab worker without prompt starts claude with the effort" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 '' max
  [ "$status" -eq 0 ]
  grep -qx 'agent | start | claude | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | max' "$FAKE_LOG"
}

@test "handoff worker starts claude with the effort" {
  export FAKE_WRITE_DOC=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 '' low
  [ "$status" -eq 0 ]
  grep -qx 'agent | start | claude | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | low' "$FAKE_LOG"
}

@test "read_line prints the text after Enter" {
  run_in_tty "source '$PLUGIN_DIR/lib.sh'; read_line 'Prompt: ' >'$BATS_TEST_TMPDIR/line'" 'fix "auth" & $HOME\r'
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/line")" = 'fix "auth" & $HOME' ]
}

@test "read_line edits the text with the readline keys" {
  # Backspace, ctrl+w, alt+backspace, left arrow, ctrl+a and ctrl+e.
  run_in_tty "source '$PLUGIN_DIR/lib.sh'; read_line 'Prompt: ' >'$BATS_TEST_TMPDIR/line'" \
    'fixx\x7fed the bug in auth' '\x17' '\x1b\x7f' '\x1b[D\x1b[D\x1b[D\x1b[D' 'big ' '\x01' '> ' '\x05' 'now\r'
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/line")" = "> fixed the big bug now" ]
}

@test "read_line cancels on Esc" {
  run_in_tty "source '$PLUGIN_DIR/lib.sh'; read_line 'Prompt: ' >'$BATS_TEST_TMPDIR/line'" 'fix' '\x1b'
  [ "$status" -eq 1 ]
  [ ! -s "$BATS_TEST_TMPDIR/line" ]
}

@test "read_line joins the lines of a paste" {
  run_in_tty "source '$PLUGIN_DIR/lib.sh'; read_line 'Prompt: ' >'$BATS_TEST_TMPDIR/line'" \
    'fix: ' '\x1b[200~one\r\ntwo\nthree\x1b[201~' ' end\r'
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/line")" = 'fix: one two three end' ]
}

@test "read_line cancels on Esc after a paste" {
  run_in_tty "source '$PLUGIN_DIR/lib.sh'; read_line 'Prompt: ' >'$BATS_TEST_TMPDIR/line'" \
    'fix: ' '\x1b[200~one\ntwo\x1b[201~' '\x1b'
  [ "$status" -eq 1 ]
  [ ! -s "$BATS_TEST_TMPDIR/line" ]
}

@test "read_effort cancels on Esc" {
  run bash -c 'source "$1/lib.sh"; read_effort 2>/dev/null' _ "$PLUGIN_DIR" < <(printf '\x1b')
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "new-tab prompt starts no worker after Esc" {
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  run_in_tty "bash '$PLUGIN_DIR/new-agent-tab.sh' prompt" 'hello' '\x1b'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enter to confirm. Esc or ctrl+c to cancel."* ]]
  [ ! -e "$HERDR_PLUGIN_STATE_DIR/new-tab.log" ]
}

@test "handoff prompt starts no worker after Esc in the effort question" {
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  run_in_tty "bash '$PLUGIN_DIR/handoff.sh' prompt" 'focus\r' '\x1b'
  [ "$status" -eq 0 ]
  [ ! -e "$HERDR_PLUGIN_STATE_DIR/handoff.log" ]
}

@test "new-tab worker names the tab with the claude session title" {
  export FAKE_TITLE="Postgres port issue"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'why does postgres not start'
  [ "$status" -eq 0 ]
  grep -qx 'agent | get | w1:p9' "$FAKE_LOG"
  grep -qx 'agent | rename | w1:p9 | postgres-port-issue' "$FAKE_LOG"
}

@test "new-tab worker names the tab with the prompt when claude gives no title" {
  export FAKE_AGENT_KIND="claude" FAKE_TITLE="claude"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 $'fix the login\n  test now'
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | fix-the-login-test-now' "$FAKE_LOG"
}

@test "new-tab worker skips the Claude Code placeholder title" {
  export FAKE_AGENT_KIND="claude" FAKE_TITLE="Claude Code"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'fix the login'
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | fix-the-login' "$FAKE_LOG"
}

@test "new-tab worker adds a number when the agent name is taken" {
  export FAKE_TITLE="Postgres port issue" FAKE_NAME_TAKEN="postgres-port-issue"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello'
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | postgres-port-issue-2' "$FAKE_LOG"
}

@test "new-tab worker cuts a long tab name at a word" {
  export FAKE_TITLE="Neg-risk markets query and indexer setup questions"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello'
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | neg-risk-markets-query-and' "$FAKE_LOG"
}

@test "new-tab worker makes a valid agent name from any title" {
  export FAKE_TITLE="  2 Fixes: Herdr's tab/agent naming!  "
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello'
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | fixes-herdr-s-tab-agent-naming' "$FAKE_LOG"
}

@test "new-tab worker without prompt keeps the tab number" {
  export FAKE_TITLE="Some title"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  [ "$(grep -v -- '--clear' "$FAKE_LOG" | grep -c '^agent | rename')" -eq 0 ]
}

@test "handoff worker names the tab with the claude session title" {
  export FAKE_WRITE_DOC=1 FAKE_TITLE="Login test fix"
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | login-test-fix' "$FAKE_LOG"
}

@test "handoff worker renames the new session with the focus before the first prompt" {
  export FAKE_WRITE_DOC=1 FAKE_TITLE="Postgres port issue"
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 'fix the migrations'
  [ "$status" -eq 0 ]
  local rename read
  rename=$(grep -nx 'agent | prompt | w1:p9 | /rename fix the migrations' "$FAKE_LOG" | cut -d: -f1)
  read=$(grep -n '^agent | prompt | w1:p9 | Read the handoff document' "$FAKE_LOG" | cut -d: -f1)
  [ -n "$rename" ] && [ -n "$read" ] && [ "$rename" -lt "$read" ]
}

@test "handoff worker without focus renames the new session with the source title and handoff" {
  export FAKE_WRITE_DOC=1 FAKE_TITLE="Postgres port issue"
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx 'agent | prompt | w1:p9 | /rename Postgres port issue handoff' "$FAKE_LOG"
}

@test "handoff worker sends no /rename without focus and source title" {
  export FAKE_WRITE_DOC=1
  for title in claude "Claude Code"; do
    : >"$FAKE_LOG"
    FAKE_TITLE="$title" run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
    [ "$status" -eq 0 ]
    [ "$(grep -c '^agent | prompt | w1:p9 | /rename' "$FAKE_LOG")" -eq 0 ]
  done
}

@test "handoff worker keeps the tab number without title and focus" {
  export FAKE_WRITE_DOC=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  [ "$(grep -v -- '--clear' "$FAKE_LOG" | grep -c '^agent | rename')" -eq 0 ]
}

@test "new-tab worker gives the focus to the new tab with --focus" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'hello' '' --focus
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $HOME | --focus" "$FAKE_LOG"
}

@test "handoff worker gives the focus to the new tab with --focus" {
  export FAKE_WRITE_DOC=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 '' '' --focus
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $HOME | --focus" "$FAKE_LOG"
}

@test "read_focus prints --focus for y" {
  run bash -c 'source "$1/lib.sh"; read_focus 2>/dev/null' _ "$PLUGIN_DIR" <<<"y"
  [ "$status" -eq 0 ]
  [ "$output" = "--focus" ]
}

@test "read_focus prints --no-focus for n, for Enter and at end of input" {
  for input in n ""; do
    run bash -c 'source "$1/lib.sh"; read_focus 2>/dev/null' _ "$PLUGIN_DIR" <<<"$input"
    [ "$status" -eq 0 ]
    [ "$output" = "--no-focus" ]
  done
  run bash -c 'source "$1/lib.sh"; read_focus 2>/dev/null' _ "$PLUGIN_DIR" </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "--no-focus" ]
}

@test "read_focus asks again after an incorrect key" {
  run bash -c 'source "$1/lib.sh"; read_focus 2>/dev/null' _ "$PLUGIN_DIR" <<<"zy"
  [ "$status" -eq 0 ]
  [ "$output" = "--focus" ]
}

@test "read_focus cancels on Esc" {
  run bash -c 'source "$1/lib.sh"; read_focus 2>/dev/null' _ "$PLUGIN_DIR" < <(printf '\x1b')
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "new-tab prompt starts no worker after Esc in the focus question" {
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  run_in_tty "bash '$PLUGIN_DIR/new-agent-tab.sh' prompt" 'hello\r' '\r' '\x1b'
  [ "$status" -eq 0 ]
  [ ! -e "$HERDR_PLUGIN_STATE_DIR/new-tab.log" ]
}

@test "handoff prompt starts no worker after Esc in the focus question" {
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  run_in_tty "bash '$PLUGIN_DIR/handoff.sh' prompt" 'focus\r' '\r' '\x1b'
  [ "$status" -eq 0 ]
  [ ! -e "$HERDR_PLUGIN_STATE_DIR/handoff.log" ]
}

@test "sync-name loop names the agent with the title until claude exits" {
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
  [ "$(grep -c '^agent | get | w1:p5$' "$FAKE_LOG")" -eq 3 ]
}

@test "sync-name loop follows a new title after /rename" {
  export FAKE_START_NAME=claude FAKE_NAME="postgres-port-issue" FAKE_TITLE="db-migration-fix" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'agent | rename | w1:p5 | db-migration-fix' "$FAKE_LOG")" -eq 2 ]
}

@test "sync-name loop keeps a name that matches the title" {
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  for name in postgres-port-issue postgres-port-issue-2; do
    : >"$FAKE_LOG"
    FAKE_NAME="$name" run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
    [ "$status" -eq 0 ]
    [ "$(grep -c '^agent | rename' "$FAKE_LOG")" -eq 0 ]
  done
}

@test "sync-name loop keeps the name while the title is a placeholder" {
  export FAKE_START_NAME=claude FAKE_NAME="fix-the-login" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0
  for title in claude "Claude Code"; do
    : >"$FAKE_LOG"
    FAKE_TITLE="$title" run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
    [ "$status" -eq 0 ]
    [ "$(grep -c '^agent | rename' "$FAKE_LOG")" -eq 0 ]
  done
}

@test "sync-name loop keeps the name from herdr agent start and stops" {
  export FAKE_NAME="repo-scout" FAKE_TITLE="Ansible role for weekly" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | rename' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c '^agent | get | w1:p5$' "$FAKE_LOG")" -eq 1 ]
}

@test "sync-name loop adds a number when the agent name is taken" {
  export FAKE_TITLE="Postgres port issue" FAKE_NAME_TAKEN="postgres-port-issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue-2' "$FAKE_LOG"
}

@test "sync-name loop stops when herdr finds no claude in the pane" {
  export AGENT_TABS_START_TIMEOUT=0 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 1 ]
  FAKE_AGENT_KIND=codex FAKE_TITLE="Some title" run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | rename' "$FAKE_LOG")" -eq 0 ]
}

@test "sync-name start does nothing outside Herdr" {
  unset HERDR_ENV
  run bash "$PLUGIN_DIR/sync-name.sh" start </dev/null
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "sync-name start runs the loop for the current pane in the background" {
  export HERDR_ENV=1 XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" start <<<'{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  for _ in $(seq 50); do
    grep -q '^agent | rename | w1:p1' "$FAKE_LOG" && break
    sleep 0.1
  done
  grep -qx 'agent | rename | w1:p1 | postgres-port-issue' "$FAKE_LOG"
}

# Make a git repo with a subfolder. Print the repo root as git gives it.
make_repo() {
  git init -q "$BATS_TEST_TMPDIR/repo"
  mkdir -p "$BATS_TEST_TMPDIR/repo/src"
  git -C "$BATS_TEST_TMPDIR/repo" rev-parse --show-toplevel
}

# Print a pane list: the agent pane w1:p1 in tab w1:t1, then the panes "ID TAB CWD" in $@.
panes_json() {
  local p items='{"pane_id":"w1:p1","tab_id":"w1:t1","foreground_cwd":"/agent"}'
  for p in "$@"; do
    read -r id tab cwd <<<"$p"
    items+=",{\"pane_id\":\"$id\",\"tab_id\":\"$tab\",\"foreground_cwd\":\"$cwd\"}"
  done
  printf '{"result":{"panes":[%s]}}\n' "$items"
}

# Make a commit in the repo and add the worktree repo-wt next to it. Print its root.
make_worktree() {
  git -C "$BATS_TEST_TMPDIR/repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$BATS_TEST_TMPDIR/repo" worktree add -q "$BATS_TEST_TMPDIR/repo-wt"
  mkdir -p "$BATS_TEST_TMPDIR/repo-wt/src"
  git -C "$BATS_TEST_TMPDIR/repo-wt" rev-parse --show-toplevel
}

# Print the worktree file of pane w1:p1.
wt_file() {
  printf '%s\n' "$HOME/.local/state/herdr/plugins/awea.agent-tabs/worktrees/w1_p1"
}

# Write folder $1 as the recorded worktree of pane w1:p1.
record_worktree() {
  mkdir -p "$(dirname "$(wt_file)")"
  printf '%s\n' "$1" >"$(wt_file)"
}

@test "reviewr opens a zoomed split right of the pane for the worktree root of the pane cwd" {
  root=$(make_repo)
  export FAKE_CWD="$root/src"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -qx "plugin | pane | open | --plugin | persiyanov.reviewr | --entrypoint | pane | --placement | zoomed | --target-pane | w1:p1 | --direction | right | --cwd | $root | --focus" "$FAKE_LOG"
  [[ "$output" == *"w1:p8"*"$root"* ]]
}

@test "reviewr uses the recorded worktree of the pane, not the pane cwd" {
  root=$(make_repo)
  worktree=$(make_worktree)
  record_worktree "$worktree"
  export FAKE_CWD="$root"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q "^plugin | pane | open | .* | --cwd | $worktree | --focus$" "$FAKE_LOG"
}

@test "reviewr uses the pane cwd when the recorded folder no longer exists" {
  root=$(make_repo)
  record_worktree "$BATS_TEST_TMPDIR/gone"
  export FAKE_CWD="$root/src"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q "^plugin | pane | open | .* | --cwd | $root | --focus$" "$FAKE_LOG"
}

@test "reviewr opens nothing when no pane has focus" {
  unset HERDR_PANE_ID
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 1 ]
  grep -q '^notification | show' "$FAKE_LOG"
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr opens nothing outside a git repo" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  export FAKE_CWD="$BATS_TEST_TMPDIR/plain"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in a git repo"* ]]
  grep -q '^notification | show' "$FAKE_LOG"
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr keeps the reviewr of the same worktree in the same tab" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $root")
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"w1:p4"* ]]
  grep -qx 'pane | zoom | w1:p4 | --on' "$FAKE_LOG"
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr opens nothing when the focused pane is a reviewr" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_REVIEWR_PANES="w1:p1"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr opens when the other reviewr is in another tab or for another worktree" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4 w1:p5"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t2 $root" "w1:p5 w1:t1 /other/worktree")
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q '^plugin | pane | open' "$FAKE_LOG"
}

@test "reviewr does not count a pane in the worktree that is not reviewr" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_PANES_JSON
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $root")
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q '^plugin | pane | open' "$FAKE_LOG"
}

@test "reviewr shows the cause when Herdr does not open the pane" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_PLUGIN_OPEN_FAIL=1
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plugin_not_found"* ]]
}

# Run the worktree hook in mode $1 with the hook JSON $2 on stdin.
# Set CLAUDE_PROJECT_DIR to the repo first.
track() {
  run bash "$PLUGIN_DIR/track-worktree.sh" "$1" <<<"$2"
}

# Print the hook JSON for tool $1 with the tool input $2 and the cwd $3.
tool_json() {
  jq -cn --arg tool "$1" --argjson input "$2" --arg cwd "$3" \
    '{hook_event_name: "PostToolUse", cwd: $cwd, tool_name: $tool, tool_input: $input}'
}

# Print the hook JSON for a Bash command $1 with the cwd $2.
bash_json() {
  tool_json Bash "$(jq -cn --arg c "$1" '{command: $c}')" "$2"
}

@test "track-worktree records the linked worktree of an Edit" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(tool_json Edit "{\"file_path\":\"$worktree/src/a.txt\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree records the folder of a NotebookEdit" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(tool_json NotebookEdit "{\"notebook_path\":\"$worktree/n.ipynb\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree uses the nearest existing parent of a deleted file" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(tool_json Write "{\"file_path\":\"$worktree/gone/deep/a.txt\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree records the cd target of a Bash command" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(bash_json "cd $worktree && git commit -m x" "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree records a git -C target in quotes" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(bash_json "git -C \"$worktree/src\" status" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree resolves a relative and a home target" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(bash_json "cd ../repo-wt/src && ls" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
  mkdir -p "$HOME"
  ln -s "$worktree" "$HOME/wt"
  rm "$(wt_file)"
  track tool "$(bash_json "git -C ~/wt log" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree takes the last valid target and skips other repos and plain folders" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  git init -q "$BATS_TEST_TMPDIR/other"
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  track tool "$(bash_json "cd $CLAUDE_PROJECT_DIR && cd $worktree && git -C $BATS_TEST_TMPDIR/other log; cd '$BATS_TEST_TMPDIR/plain'; cd \$X; cd /no/such" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree keeps the old file for a Bash command without a target in the project" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  record_worktree "$worktree"
  track tool "$(bash_json "git status" "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree records the hook cwd when it differs from the project" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(bash_json "git status" "$worktree/src")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree writes nothing outside Herdr" {
  unset HERDR_ENV
  export CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  track tool "$(tool_json Edit "{\"file_path\":\"$CLAUDE_PROJECT_DIR/a\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ ! -e "$(wt_file)" ]
}

@test "track-worktree start deletes the file of the pane" {
  export HERDR_ENV=1
  record_worktree /old
  track start '{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(wt_file)" ]
}

@test "track-worktree start keeps the file on compact and resume" {
  export HERDR_ENV=1
  record_worktree /old
  track start '{"hook_event_name":"SessionStart","source":"compact"}'
  [ -e "$(wt_file)" ]
  track start '{"hook_event_name":"SessionStart","source":"resume"}'
  [ -e "$(wt_file)" ]
  track start '{"hook_event_name":"SessionStart","source":"fork"}'
  [ -e "$(wt_file)" ]
  track start '{"hook_event_name":"SessionStart","source":"clear"}'
  [ ! -e "$(wt_file)" ]
}

@test "track-worktree end deletes the file of the pane" {
  export HERDR_ENV=1
  record_worktree /old
  track end '{"hook_event_name":"SessionEnd"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(wt_file)" ]
}

@test "track-worktree uses HOME and not XDG_STATE_HOME" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg"
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(tool_json Edit "{\"file_path\":\"$worktree/a\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree resolves a relative target against the previous cd" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(bash_json "cd $worktree && cd src && ls" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
  rm "$(wt_file)"
  track tool "$(bash_json "cd $worktree && git -C src status" "$CLAUDE_PROJECT_DIR")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree ignores cd in heredocs, quoted strings and comments" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  root=$CLAUDE_PROJECT_DIR
  for cmd in \
    "cd $worktree && git commit -m \"\$(cat <<'EOF'
fix: x; cd $root
EOF
)\"" \
    "cd $worktree && cat > notes <<EOF
x; cd $root
EOF" \
    "cd $worktree; echo 'x; cd $root now'" \
    "cd $worktree && git commit -m \"a && cd $root now\"" \
    "cd $worktree # ; cd $root" \
    "cd $root && cat > notes <<-EOF
	x; cd $root
	EOF
cd $worktree" \
    "echo \"x \\\"; cd $root; \\\" y\" && cd $worktree" \
    "cd $root && echo \"a \\\" b\" && cd $worktree" \
    "cd $root; echo it\\'s; cd $worktree" \
    "cd $root && echo \$'it\\'s' && cd $worktree" \
    "cd $root && cat <<< \"text\"
cd $worktree"; do
    rm -f "$(wt_file)"
    track tool "$(bash_json "$cmd" "$root")"
    [ "$(cat "$(wt_file)")" = "$worktree" ] || { echo "failed: $cmd"; false; }
  done
}

@test "track-worktree accepts a tab, cd --, and git options before -C" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  for cmd in "ls &&	cd $worktree" "cd -- $worktree" "git --no-pager -C $worktree log" "git -c a.b=c -C $worktree log"; do
    rm -f "$(wt_file)"
    track tool "$(bash_json "$cmd" "$CLAUDE_PROJECT_DIR")"
    [ "$(cat "$(wt_file)")" = "$worktree" ]
  done
}

@test "track-worktree keeps the old file for a command in a subfolder of the project" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  record_worktree "$worktree"
  track tool "$(bash_json "ls" "$CLAUDE_PROJECT_DIR/src")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree uses the hook cwd when no target is valid" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(bash_json "cd \$X && ls" "$worktree/src")"
  [ "$(cat "$(wt_file)")" = "$worktree" ]
}

@test "track-worktree exits 0 with empty stdout on bad JSON" {
  export HERDR_ENV=1
  run bash -c 'bash "$1" tool <<<"not json{" 2>/dev/null' _ "$PLUGIN_DIR/track-worktree.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'bash "$1" start </dev/null 2>/dev/null' _ "$PLUGIN_DIR/track-worktree.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "new-tab worker starts claude in the main worktree root from a linked worktree" {
  root=$(make_repo)
  worktree=$(make_worktree)
  export FAKE_CWD="$worktree/src"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $root | --no-focus" "$FAKE_LOG"
}

@test "new-tab worker keeps the pane folder in the main worktree" {
  root=$(make_repo)
  make_worktree >/dev/null
  export FAKE_CWD="$root/src"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $root/src | --no-focus" "$FAKE_LOG"
}

@test "new-tab worker keeps the pane folder outside a git repo" {
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  export FAKE_CWD="$BATS_TEST_TMPDIR/plain"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $BATS_TEST_TMPDIR/plain | --no-focus" "$FAKE_LOG"
}

@test "new-shell-tab opens a focused tab in the main worktree root from a linked worktree" {
  root=$(make_repo)
  worktree=$(make_worktree)
  export FAKE_CWD="$worktree/src"
  run bash "$PLUGIN_DIR/new-shell-tab.sh"
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $root | --focus" "$FAKE_LOG"
  [ "$(grep -c '^agent' "$FAKE_LOG")" -eq 0 ]
}

@test "new-shell-tab keeps the pane folder in the main worktree" {
  root=$(make_repo)
  make_worktree >/dev/null
  export FAKE_CWD="$root/src"
  run bash "$PLUGIN_DIR/new-shell-tab.sh"
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $root/src | --focus" "$FAKE_LOG"
}

@test "new-shell-tab keeps the pane folder outside a git repo" {
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  export FAKE_CWD="$BATS_TEST_TMPDIR/plain"
  run bash "$PLUGIN_DIR/new-shell-tab.sh"
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $BATS_TEST_TMPDIR/plain | --focus" "$FAKE_LOG"
}

@test "new-shell-tab without a focused pane opens a tab in the workspace" {
  unset HERDR_PANE_ID
  run bash "$PLUGIN_DIR/new-shell-tab.sh"
  [ "$status" -eq 0 ]
  grep -qx 'tab | create | --workspace | w1 | --focus' "$FAKE_LOG"
  [ "$(grep -c '^pane | get' "$FAKE_LOG")" -eq 0 ]
}

@test "new-shell-tab shows a notification without a workspace" {
  unset HERDR_WORKSPACE_ID HERDR_PANE_ID
  run bash "$PLUGIN_DIR/new-shell-tab.sh"
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs | --body | ' "$FAKE_LOG"
  [ "$(grep -c '^tab | create' "$FAKE_LOG")" -eq 0 ]
}

@test "new-shell-tab shows a notification when the tab does not open" {
  export FAKE_TAB_CREATE_FAIL=1
  run bash "$PLUGIN_DIR/new-shell-tab.sh"
  [ "$status" -eq 1 ]
  grep -q '^notification | show | Agent tabs | --body | ' "$FAKE_LOG"
}

@test "focus-link focuses the tab and the agent of a pane link" {
  export HERDR_PLUGIN_CLICKED_URL="https://herdr.invalid/pane/wQ:p2N" FAKE_AGENT_KIND=claude
  run bash "$PLUGIN_DIR/focus-link.sh"
  [ "$status" -eq 0 ]
  grep -qx 'pane | get | wQ:p2N' "$FAKE_LOG"
  grep -qx 'tab | focus | w1:t9' "$FAKE_LOG"
  grep -qx 'agent | focus | wQ:p2N' "$FAKE_LOG"
}

@test "focus-link focuses the tab of a pane link without an agent" {
  export HERDR_PLUGIN_CLICKED_URL="https://herdr.invalid/pane/wQ:p2"
  run bash "$PLUGIN_DIR/focus-link.sh"
  [ "$status" -eq 0 ]
  grep -qx 'tab | focus | w1:t9' "$FAKE_LOG"
}

@test "focus-link focuses the tab of a tab link" {
  export HERDR_PLUGIN_CLICKED_URL="https://herdr.invalid/tab/wQ:t3"
  run bash "$PLUGIN_DIR/focus-link.sh"
  [ "$status" -eq 0 ]
  grep -qx 'tab | focus | wQ:t3' "$FAKE_LOG"
  [ "$(grep -c '^pane | get\|^agent' "$FAKE_LOG")" -eq 0 ]
}

@test "focus-link shows a notification when the pane does not exist" {
  export HERDR_PLUGIN_CLICKED_URL="https://herdr.invalid/pane/wQ:p2" FAKE_PANE_MISSING=1
  run bash "$PLUGIN_DIR/focus-link.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-tabs: The pane wQ:p2 does not exist."* ]]
  [ "$(grep -c '^tab | focus' "$FAKE_LOG")" -eq 0 ]
}

@test "focus-link shows a notification when the tab does not exist" {
  export HERDR_PLUGIN_CLICKED_URL="https://herdr.invalid/tab/wQ:t3" FAKE_TAB_MISSING=1
  run bash "$PLUGIN_DIR/focus-link.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-tabs: The tab wQ:t3 does not exist."* ]]
}

@test "focus-link shows a notification for a URL that is not a Herdr link" {
  for url in "https://herdr.invalid/pane/" "https://herdr.invalid/window/wQ:p2" "https://example.com/pane/wQ:p2" ""; do
    : >"$FAKE_LOG"
    HERDR_PLUGIN_CLICKED_URL="$url" run bash "$PLUGIN_DIR/focus-link.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent-tabs: Not a Herdr pane or tab link: $url"* ]]
    [ "$(grep -c '^tab | focus\|^pane | get' "$FAKE_LOG")" -eq 0 ]
  done
}

@test "open-file opens the file of a file link in the editor" {
  export AGENT_TABS_EDITOR="$BATS_TEST_DIRNAME/fake-herdr"
  dir="$BATS_TEST_TMPDIR/docs"
  mkdir -p "$dir"
  touch "$dir/my spec.md" "$dir/x.ex"
  for url in "file://${dir// /%20}/my%20spec.md|$dir/my spec.md" \
    "file://host$dir/x.ex|$dir/x.ex" \
    "file://$dir/x.ex:12|$dir/x.ex:12" \
    "file://$dir/x.ex#L12|$dir/x.ex:12"; do
    : >"$FAKE_LOG"
    HERDR_PLUGIN_CLICKED_URL="${url%%|*}" run bash "$PLUGIN_DIR/open-file.sh"
    [ "$status" -eq 0 ]
    grep -qx "${url#*|}" "$FAKE_LOG"
  done
}

@test "open-file shows a notification when the file does not exist" {
  export AGENT_TABS_EDITOR="$BATS_TEST_DIRNAME/fake-herdr"
  HERDR_PLUGIN_CLICKED_URL="file:///no/such/file.md" run bash "$PLUGIN_DIR/open-file.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-tabs: The file /no/such/file.md does not exist."* ]]
  [ "$(grep -c . "$FAKE_LOG")" -eq 1 ]
}

@test "open-file shows a notification for a URL that is not a file link" {
  export AGENT_TABS_EDITOR="$BATS_TEST_DIRNAME/fake-herdr"
  for url in "https://example.com/x.md" "file://" ""; do
    : >"$FAKE_LOG"
    HERDR_PLUGIN_CLICKED_URL="$url" run bash "$PLUGIN_DIR/open-file.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent-tabs: Not a file link: $url"* ]]
  done
}
