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
  export AGENT_TABS_GH="$BATS_TEST_DIRNAME/fake-gh"
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"
  touch "$HERDR_PLUGIN_CONFIG_DIR/debug"
  : >"$FAKE_LOG"
}

# Run the bash code $1 in a terminal. Type each next argument (a printf format) after
# a pause, so that the code is ready to read it. Set status to the exit code of the
# code, and output to the terminal output. The script of macOS (BSD) takes the command
# after the file, and always exits with the exit code of the command.
run_in_tty() {
  local cmd=(script -qec 'bash -c "$TTY_CODE"' /dev/null)
  [ "$(uname -s)" != Darwin ] || cmd=(script -q /dev/null bash -c "$1")
  export TTY_CODE="$1"
  shift
  run "${cmd[@]}" < <(
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

@test "sync-name loop stops when a running loop has the lock folder" {
  lock="$BATS_TEST_TMPDIR/sync.lock.d"
  mkdir "$lock"
  printf '%s\n' "$$" >"$lock/pid"
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5 "$lock"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
  [ "$(cat "$lock/pid")" = "$$" ]
}

@test "sync-name loop takes the lock folder of a stopped loop and removes it at the end" {
  lock="$BATS_TEST_TMPDIR/sync.lock.d"
  mkdir "$lock"
  # The PID of a process that has stopped.
  bash -c 'printf "%s\n" "$$"' >"$lock/pid"
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5 "$lock"
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
  [ ! -e "$lock" ]
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

# Write the turn base $2 (empty for no ref) as the record of the reviewr pane $1.
record_reviewr() {
  local file="$HOME/.local/state/herdr/plugins/awea.agent-tabs/reviewr/${1//:/_}"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$2" >"$file"
}

@test "reviewr keeps the reviewr of the same worktree in the same tab" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $root")
  record_reviewr w1:p4 ""
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

@test "open-file runs the editor directly without systemd-run (macOS)" {
  export AGENT_TABS_EDITOR="$BATS_TEST_DIRNAME/fake-herdr"
  export AGENT_TABS_LAUNCHER="$BATS_TEST_TMPDIR/no-systemd-run"
  touch "$BATS_TEST_TMPDIR/x.ex"
  HERDR_PLUGIN_CLICKED_URL="file://$BATS_TEST_TMPDIR/x.ex:3" run bash "$PLUGIN_DIR/open-file.sh"
  [ "$status" -eq 0 ]
  grep -qx "$BATS_TEST_TMPDIR/x.ex:3" "$FAKE_LOG"
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

# Run git in folder $1 with the arguments $2... and a fixed author, without signatures.
tgit() {
  local dir="$1"
  shift
  git -C "$dir" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"
}

# Make the repo with one commit on master, and the branch dev. Print its root.
make_base_repo() {
  git init -q -b master "$BATS_TEST_TMPDIR/repo"
  tgit "$BATS_TEST_TMPDIR/repo" commit -q --allow-empty -m init
  tgit "$BATS_TEST_TMPDIR/repo" branch dev
  git -C "$BATS_TEST_TMPDIR/repo" rev-parse --show-toplevel
}

# Make the branch $1 from the start point $2 and the worktree repo-$1 for it. Print its root.
make_branch_worktree() {
  tgit "$BATS_TEST_TMPDIR/repo" branch "$1" "$2"
  git -C "$BATS_TEST_TMPDIR/repo" worktree add -q "$BATS_TEST_TMPDIR/repo-$1" "$1"
  git -C "$BATS_TEST_TMPDIR/repo-$1" rev-parse --show-toplevel
}

# Print the reviewr base pick of worktree $1, or nothing without a pick.
base_pick() {
  git -C "$1" cat-file blob refs/worktree/reviewr/base-pick 2>/dev/null || true
}

@test "reviewr writes the base pick from the branch reflog before the pane opens" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat dev)
  export FAKE_CWD="$worktree"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [ "$(base_pick "$worktree")" = dev ]
}

@test "reviewr strips origin/ from the reflog base" {
  root=$(make_base_repo)
  tgit "$root" update-ref refs/remotes/origin/dev dev
  worktree=$(make_branch_worktree feat origin/dev)
  export FAKE_CWD="$worktree"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$(base_pick "$worktree")" = dev ]
}

@test "reviewr keeps a base pick that exists" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat dev)
  blob=$(printf 'other' | git -C "$worktree" hash-object -w --stdin)
  git -C "$worktree" update-ref refs/worktree/reviewr/base-pick "$blob"
  export FAKE_CWD="$worktree"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [ "$(base_pick "$worktree")" = other ]
}

@test "reviewr writes no base pick for a branch created from HEAD" {
  root=$(make_base_repo)
  git -C "$root" worktree add -q -b feat "$BATS_TEST_TMPDIR/repo-feat"
  git -C "$root" reflog show --format=%gs refs/heads/feat | grep -qx 'branch: Created from HEAD'
  export FAKE_CWD="$BATS_TEST_TMPDIR/repo-feat"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [ -z "$(base_pick "$BATS_TEST_TMPDIR/repo-feat")" ]
}

@test "reviewr writes no base pick for a branch created from the default branch" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat master)
  export FAKE_CWD="$worktree"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [ -z "$(base_pick "$worktree")" ]
}

@test "reviewr starts the base worker for the worktree" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat dev)
  export FAKE_CWD="$worktree"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q "^gh | pr | view | .* | in $worktree$" "$FAKE_LOG" && break
    sleep 0.2
  done
  grep -q "^gh | pr | view | --json | baseRefName | -q | .baseRefName | in $worktree$" "$FAKE_LOG"
}

@test "reviewr base writes the base branch of the pull request" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat master)
  export FAKE_GH_BASE=dev
  run bash "$PLUGIN_DIR/reviewr.sh" base "$worktree"
  [ "$status" -eq 0 ]
  [ "$(base_pick "$worktree")" = dev ]
}

@test "reviewr base deletes the pick when the pull request targets the default branch" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat dev)
  blob=$(printf 'dev' | git -C "$worktree" hash-object -w --stdin)
  git -C "$worktree" update-ref refs/worktree/reviewr/base-pick "$blob"
  export FAKE_GH_BASE=master
  run bash "$PLUGIN_DIR/reviewr.sh" base "$worktree"
  [ "$status" -eq 0 ]
  ! git -C "$worktree" rev-parse --verify -q refs/worktree/reviewr/base-pick
}

@test "reviewr base changes nothing without a pull request" {
  make_base_repo >/dev/null
  worktree=$(make_branch_worktree feat dev)
  blob=$(printf 'dev' | git -C "$worktree" hash-object -w --stdin)
  git -C "$worktree" update-ref refs/worktree/reviewr/base-pick "$blob"
  run bash "$PLUGIN_DIR/reviewr.sh" base "$worktree"
  [ "$status" -eq 0 ]
  [ "$(base_pick "$worktree")" = dev ]
}

# Print the turn file of pane w1:p1.
turn_file() {
  printf '%s\n' "$HOME/.local/state/herdr/plugins/awea.agent-tabs/turns/w1_p1"
}

# Print the hook JSON for event $1 with the cwd $2.
event_json() {
  jq -cn --arg event "$1" --arg cwd "$2" '{hook_event_name: $event, cwd: $cwd}'
}

# Print the tree of the files in worktree $1, as a snapshot sees it.
tree_of() {
  local index="$BATS_TEST_TMPDIR/check-index"
  rm -f "$index"
  GIT_INDEX_FILE=$index git -C "$1" add -A
  GIT_INDEX_FILE=$index git -C "$1" write-tree
  rm -f "$index"
}

@test "track-worktree prompt writes a snapshot of the recorded worktree and the cwd worktree" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  echo a >"$worktree/src/a.txt"
  record_worktree "$worktree"
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR/src")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$(turn_file)")" = "$(printf '%s\t%s\n%s\t%s' "$worktree" "$(tree_of "$worktree")" \
    "$CLAUDE_PROJECT_DIR" "$(tree_of "$CLAUDE_PROJECT_DIR")")" ]
  track prompt "$(event_json UserPromptSubmit "$worktree")"
  [ "$(wc -l <"$(turn_file)")" -eq 1 ]
}

@test "track-worktree prompt leaves the real index and the git dir as they were" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  echo a >"$CLAUDE_PROJECT_DIR/a.txt"
  git -C "$CLAUDE_PROJECT_DIR" add a.txt
  echo b >"$CLAUDE_PROJECT_DIR/b.txt"
  before=$(git -C "$CLAUDE_PROJECT_DIR" ls-files --stage)
  files=$(ls -A "$CLAUDE_PROJECT_DIR/.git")
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ -s "$(turn_file)" ]
  [ "$(git -C "$CLAUDE_PROJECT_DIR" ls-files --stage)" = "$before" ]
  [ "$(ls -A "$CLAUDE_PROJECT_DIR/.git")" = "$files" ]
}

@test "track-worktree pre appends the snapshot of a second worktree once" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  [ "$(wc -l <"$(turn_file)")" -eq 1 ]
  track pre "$(tool_json Edit "{\"file_path\":\"$worktree/src/a.txt\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(sed -n 2p "$(turn_file)")" = "$(printf '%s\t%s' "$worktree" "$(tree_of "$worktree")")" ]
  echo a >"$worktree/src/a.txt"
  track pre "$(bash_json "cd $worktree && ls" "$CLAUDE_PROJECT_DIR")"
  [ "$(wc -l <"$(turn_file)")" -eq 2 ]
  [ ! -e "$(wt_file)" ]
}

@test "track-worktree stop writes the turn base when the turn changed the worktree" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  start=$(tree_of "$CLAUDE_PROJECT_DIR")
  echo a >"$CLAUDE_PROJECT_DIR/src/a.txt"
  track stop "$(event_json Stop "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse refs/worktree/reviewr/turn-base)" = "$start" ]
  [ ! -e "$(turn_file)" ]
}

@test "track-worktree stop keeps the old turn base when the turn changed nothing" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  old=$(git -C "$CLAUDE_PROJECT_DIR" mktree </dev/null)
  git -C "$CLAUDE_PROJECT_DIR" update-ref refs/worktree/reviewr/turn-base "$old"
  echo a >"$CLAUDE_PROJECT_DIR/src/a.txt"
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  track stop "$(event_json Stop "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse refs/worktree/reviewr/turn-base)" = "$old" ]
}

@test "track-worktree start and end delete the turn file" {
  export HERDR_ENV=1
  mkdir -p "$(dirname "$(turn_file)")"
  echo x >"$(turn_file)"
  track start '{"hook_event_name":"SessionStart","source":"resume"}'
  [ -e "$(turn_file)" ]
  track start '{"hook_event_name":"SessionStart","source":"startup"}'
  [ ! -e "$(turn_file)" ]
  echo x >"$(turn_file)"
  track end '{"hook_event_name":"SessionEnd"}'
  [ ! -e "$(turn_file)" ]
}

@test "track-worktree turn modes write nothing outside Herdr" {
  unset HERDR_ENV
  export CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ ! -e "$(turn_file)" ]
}

@test "reviewr records the turn base of the worktree for the new pane" {
  root=$(make_repo)
  tree=$(git -C "$root" mktree </dev/null)
  git -C "$root" update-ref refs/worktree/reviewr/turn-base "$tree"
  export FAKE_CWD="$root"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.local/state/herdr/plugins/awea.agent-tabs/reviewr/w1_p8")" = "$tree" ]
}

@test "reviewr base uses the origin branch at the commit of a plain origin/HEAD" {
  root=$(make_base_repo)
  tgit "$root" update-ref refs/remotes/origin/dev dev
  tgit "$root" commit -q --allow-empty -m two
  tgit "$root" update-ref refs/remotes/origin/trunk master
  tgit "$root" update-ref refs/remotes/origin/HEAD master
  worktree=$(make_branch_worktree feat dev)
  blob=$(printf 'dev' | git -C "$worktree" hash-object -w --stdin)
  git -C "$worktree" update-ref refs/worktree/reviewr/base-pick "$blob"
  export FAKE_GH_BASE=trunk
  run bash "$PLUGIN_DIR/reviewr.sh" base "$worktree"
  [ "$status" -eq 0 ]
  ! git -C "$worktree" rev-parse --verify -q refs/worktree/reviewr/base-pick
}

@test "track-worktree stop uses only the first line of a worktree" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  start=$(tree_of "$CLAUDE_PROJECT_DIR")
  echo a >"$CLAUDE_PROJECT_DIR/src/a.txt"
  later=$(tree_of "$CLAUDE_PROJECT_DIR")
  echo b >"$CLAUDE_PROJECT_DIR/src/b.txt"
  mkdir -p "$(dirname "$(turn_file)")"
  printf '%s\t%s\n%s\t%s\n' "$CLAUDE_PROJECT_DIR" "$start" "$CLAUDE_PROJECT_DIR" "$later" >"$(turn_file)"
  track stop "$(event_json Stop "$CLAUDE_PROJECT_DIR")"
  [ "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse refs/worktree/reviewr/turn-base)" = "$start" ]
}

@test "track-worktree prompt ends the old turn first, as after an Esc" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  start=$(tree_of "$CLAUDE_PROJECT_DIR")
  echo a >"$CLAUDE_PROJECT_DIR/src/a.txt"
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse refs/worktree/reviewr/turn-base)" = "$start" ]
  [ "$(cut -f 2 "$(turn_file)")" = "$(tree_of "$CLAUDE_PROJECT_DIR")" ]
}

# Make a reviewr pane w1:p4 in the tab for the linked worktree, with an old turn base
# record. Record the linked worktree as the work of claude. Print the worktree root.
stale_reviewr() {
  local worktree
  make_repo >/dev/null
  worktree=$(make_worktree)
  git -C "$worktree" update-ref refs/worktree/reviewr/turn-base "$(git -C "$worktree" mktree </dev/null)"
  record_worktree "$worktree"
  record_reviewr w1:p4 ""
  printf '%s\n' "$worktree"
}

@test "reviewr zooms on an old reviewr and shows a toast when claude works in another worktree" {
  rm "$HERDR_PLUGIN_CONFIG_DIR/debug"
  worktree=$(stale_reviewr)
  export FAKE_CWD="$BATS_TEST_TMPDIR/repo" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $worktree")
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -qx 'pane | zoom | w1:p4 | --on' "$FAKE_LOG"
  grep -q '^notification | show | Agent tabs | --body | .*older turn' "$FAKE_LOG"
  [ "$(grep -c '^pane | close' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr shows no toast for an old reviewr when claude works in its worktree" {
  rm "$HERDR_PLUGIN_CONFIG_DIR/debug"
  worktree=$(stale_reviewr)
  export FAKE_CWD="$worktree/src" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $worktree")
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -qx 'pane | zoom | w1:p4 | --on' "$FAKE_LOG"
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr shows no toast when the record of the reviewr is current" {
  rm "$HERDR_PLUGIN_CONFIG_DIR/debug"
  worktree=$(stale_reviewr)
  record_reviewr w1:p4 "$(git -C "$worktree" rev-parse refs/worktree/reviewr/turn-base)"
  export FAKE_CWD="$BATS_TEST_TMPDIR/repo" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $worktree")
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -qx 'pane | zoom | w1:p4 | --on' "$FAKE_LOG"
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr starts no base worker when it zooms on a reviewr" {
  root=$(make_repo)
  export FAKE_CWD="$root" FAKE_PANES_JSON FAKE_REVIEWR_PANES="w1:p4"
  FAKE_PANES_JSON=$(panes_json "w1:p4 w1:t1 $root")
  record_reviewr w1:p4 ""
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  sleep 1
  [ "$(grep -c '^gh' "$FAKE_LOG")" -eq 0 ]
}

@test "reviewr base falls back to master when origin/HEAD points to no branch" {
  root=$(make_base_repo)
  git -C "$root" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
  worktree=$(make_branch_worktree feat dev)
  blob=$(printf 'dev' | git -C "$worktree" hash-object -w --stdin)
  git -C "$worktree" update-ref refs/worktree/reviewr/base-pick "$blob"
  export FAKE_GH_BASE=master
  run bash "$PLUGIN_DIR/reviewr.sh" base "$worktree"
  [ "$status" -eq 0 ]
  ! git -C "$worktree" rev-parse --verify -q refs/worktree/reviewr/base-pick
}

@test "track-worktree prompt after a stop keeps the turn base" {
  export HERDR_ENV=1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  echo a >"$CLAUDE_PROJECT_DIR/src/a.txt"
  track stop "$(event_json Stop "$CLAUDE_PROJECT_DIR")"
  # An open reviewr writes its own turn base after the stop.
  base=$(tree_of "$CLAUDE_PROJECT_DIR")
  git -C "$CLAUDE_PROJECT_DIR" update-ref refs/worktree/reviewr/turn-base "$base"
  echo b >"$CLAUDE_PROJECT_DIR/src/b.txt"
  track prompt "$(event_json UserPromptSubmit "$CLAUDE_PROJECT_DIR")"
  [ "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse refs/worktree/reviewr/turn-base)" = "$base" ]
}
