#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
# Tests for the agent-tabs plugin scripts. A fake herdr records each call.

setup() {
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # On macOS, TMPDIR is under /var, a link to /private/var, and pwd -P in the scripts
  # gives /private/var. Use the real path, so that the paths in the log match.
  BATS_TEST_TMPDIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  # macOS has no timeout: the Homebrew coreutils install it as gtimeout.
  if ! command -v timeout >/dev/null; then
    timeout() { gtimeout "$@"; }
  fi
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
  # A board.sh or dispatch.sh call can start the listener of count-watch: never a real nc.
  export DISPATCH_NC="$BATS_TEST_DIRNAME/fake-nc"
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  unset XDG_STATE_HOME DISPATCH_SESSION
  # The hidden session of the workers runs. Each call is in session.log with its session.
  export FAKE_SESSION_RUNNING=board-workers FAKE_SESSION_LOG="$FAKE_LOG.session"
  # The environment of the default Herdr server, as /proc/PID/environ gives it.
  export DISPATCH_SERVER_ENVIRON="$BATS_TEST_TMPDIR/server.environ"
  printf 'PATH=/usr/bin:/bin\0HOME=%s\0HERDR_STARTUP_CWD=/srv\0ONLY_SERVER=1\0' "$HOME" >"$DISPATCH_SERVER_ENVIRON"
  # The environment of the desktop session, as systemctl --user show-environment gives it.
  export DISPATCH_DESKTOP_ENVIRON="$BATS_TEST_TMPDIR/desktop.environ"
  : >"$DISPATCH_DESKTOP_ENVIRON"
  # The workspace w1 has the label of the test folder, so a worker opens a tab in w1.
  FAKE_WORKSPACES_JSON=$(jq -cn --arg l "$(basename "$BATS_TEST_TMPDIR")" \
    '{result: {workspaces: [{workspace_id: "w1", label: $l}]}}')
  export FAKE_WORKSPACES_JSON
  mkdir -p "$HERDR_PLUGIN_CONFIG_DIR" "$HOME"
  printf '%s' "$FAKE_LOG" >"$HOME/.fake-log-path"
  touch "$HERDR_PLUGIN_CONFIG_DIR/debug"
  : >"$FAKE_LOG"
}

# A test that fails can leave a detached name loop or nc: it would keep the output of
# bats open, and bats would wait for ever. Stop each process of the test folder.
teardown() {
  pkill -f "$BATS_TEST_TMPDIR/" 2>/dev/null || true
}

# Print the mode of the file $1, as 644. GNU stat takes -c, the macOS stat takes -f.
file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

# Write the event file $1 for the fake nc: one status event with the status $3 for the
# pane $2. A second empty file keeps the fake connection open, as a live Herdr does.
status_event() {
  printf '{"data":{"agent":"claude","agent_status":"%s","pane_id":"%s","workspace_id":"w9"},"event":"pane.agent_status_changed"}\n' \
    "$3" "$2" >"$1"
  : >"$1.more"
  export FAKE_NC_EVENTS="$1 $1.more"
}

# The view w1:p5 has a reviewr pane (w1:p6) in its tab w1:t9, as the fake reports it.
reviewr_beside_view() {
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w1:p5","tab_id":"w1:t9"},{"pane_id":"w1:p6","tab_id":"w1:t9"}]}}'
  export FAKE_REVIEWR_PANES=w1:p6
}

# Print the event folders that wait and watch left in the state folder.
event_dirs() {
  find "$HOME/.local/state/board-orchestrator" -name 'events.*' 2>/dev/null
}

# The workspace "home orchestrator" of the user (w1), and in the hidden session the
# workspace "home workers" (w9), with the agents of the JSON array $1, in the file
# FAKE_HIDDEN_AGENTS_FILE. The hidden workspace "misc" (w7) is no workers workspace.
count_watch_board() {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"home orchestrator"}]}}'
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w9","label":"home workers"},{"workspace_id":"w7","label":"misc"}]}}'
  export FAKE_HIDDEN_AGENTS_FILE="$BATS_TEST_TMPDIR/agents.json"
  jq -cn --argjson a "$1" '{result: {agents: $a}}' >"$FAKE_HIDDEN_AGENTS_FILE"
}

# The board "home": its workspace "home orchestrator" (w1) holds the orchestrator claude
# (w1:p1, tab w1:t1) and a tab w1:t5 with the pane w1:p7. The hidden worker w9:p3 is
# in the workers file, and its agent is a claude. A host restart left w1:p7 as a shell.
restore_board() {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"home orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"home-orchestrator","pane_id":"w1:p1","workspace_id":"w1"}]}}'
  export FAKE_TABS_JSON='{"result":{"tabs":[{"tab_id":"w1:t1"},{"tab_id":"w1:t5"}]}}'
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"},{"pane_id":"w1:p7","tab_id":"w1:t5"}]}}'
  export FAKE_SHELL_PANES=w1:p7 FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p3\ttask\thome\t/r.md\n' >"$HOME/.local/state/board-orchestrator/workers-board-workers"
}

# Give the folder $1 a push policy in .claude/settings.local.json.
allow_push() {
  mkdir -p "$1/.claude"
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$1/.claude/settings.local.json"
}

# Make the folder $1 a git repo with the origin remote $2 (github.com by default). No
# network.
forge_remote() {
  git init -q "$1"
  git -C "$1" remote add origin "${2:-git@github.com:o/r.git}"
}

# Write the read-only list $2 (a JSON array) to $1/.claude/settings.readonly.json.
readonly_list() {
  mkdir -p "$1/.claude"
  printf '{"permissions":{"allow":%s}}\n' "$2" >"$1/.claude/settings.readonly.json"
}

# Run the next bash scripts as on macOS: with the BSD date, stat, chmod and tail, and
# with no setsid and no tac. lib.sh puts /usr/bin first in PATH, so a PATH without a
# command does not work: exported functions take the place of the commands. On macOS,
# use the real commands.
as_macos() {
  [ "$(uname -s)" != Darwin ] || return 0
  setsid() {
    printf 'setsid: command not found\n' >&2
    return 127
  }
  tac() {
    printf 'tac: command not found\n' >&2
    return 127
  }
  command() {
    if [ "$1" = -v ] && { [ "$2" = setsid ] || [ "$2" = tac ]; }; then
      return 1
    fi
    builtin command "$@"
  }
  # BSD date: no long options, -r takes seconds, and %N is a plain N.
  date() {
    local a args=()
    for a in "$@"; do
      case "$a" in
        --*)
          printf 'date: illegal option -- -\n' >&2
          return 1
          ;;
      esac
      args+=("${a//%N/N}")
    done
    if [ "${1:-}" = -r ] && [[ "${2:-}" == *[!0-9]* ]]; then
      printf 'date: illegal time format\n' >&2
      return 1
    fi
    builtin command date "${args[@]}"
  }
  # BSD stat: -f FORMAT, with %m (mtime), %Fm (mtime with a fraction), %Lp (mode).
  stat() {
    if [ "${1:-}" != -f ]; then
      printf 'stat: illegal option -- %s\n' "${1#-}" >&2
      return 1
    fi
    case "$2" in
      %m) builtin command stat -c %Y "$3" ;;
      %Fm) builtin command stat -c %.9Y "$3" ;;
      %Lp) builtin command stat -c %a "$3" ;;
      *) return 1 ;;
    esac
  }
  chmod() {
    if [[ "${1:-}" == --* ]]; then
      printf 'chmod: illegal option -- -\n' >&2
      return 1
    fi
    builtin command chmod "$@"
  }
  # BSD tail has -r: the lines in reverse order.
  tail() {
    if [ "${1:-}" = -r ]; then
      shift
      builtin command tac "$@"
    else
      builtin command tail "$@"
    fi
  }
  export -f setsid tac command date stat chmod tail
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
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000' "$FAKE_LOG"
  grep -qx 'agent | rename | w1:p9 | --clear' "$FAKE_LOG"
  grep -qx 'agent | prompt | w1:p9 | fix "auth" & $HOME' "$FAKE_LOG"
}

@test "new-tab worker without prompt opens a clean background tab" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 ''
  [ "$status" -eq 0 ]
  grep -qx "tab | create | --workspace | w1 | --cwd | $HOME | --no-focus" "$FAKE_LOG"
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000' "$FAKE_LOG"
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
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000' "$FAKE_LOG"
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
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | high' "$FAKE_LOG"
}

@test "new-tab worker without prompt starts claude with the effort" {
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 '' max
  [ "$status" -eq 0 ]
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | max' "$FAKE_LOG"
}

@test "handoff worker starts claude with the effort" {
  export FAKE_WRITE_DOC=1
  run bash "$PLUGIN_DIR/handoff.sh" worker w1:p1 w1 '' low
  [ "$status" -eq 0 ]
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | low' "$FAKE_LOG"
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

@test "sync-name loop in a pane of the hidden session names the agent there" {
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0 HERDR_SESSION=board-workers
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | agent | rename | w1:p5 | postgres-port-issue' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | agent' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "sync-name loop follows a new title after /rename" {
  export FAKE_START_NAME=claude FAKE_NAME="postgres-port-issue" FAKE_TITLE="db-migration-fix" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'agent | rename | w1:p5 | db-migration-fix' "$FAKE_LOG")" -eq 2 ]
}

@test "sync-name loop renames a claude that still has its start name" {
  export FAKE_START_NAME=claude-start-w1-p5 FAKE_NAME=claude-start-w1-p5 FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=2 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" loop w1:p5
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
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

# The session listener of the name sync: the lock folder is the test folder. The event
# file $1 gets one pane_updated event for each "PANE TITLE" argument after it.
name_listener() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  local file=$1 item
  shift
  : >"$file"
  for item in "$@"; do
    jq -cn --arg p "${item%% *}" --arg t "${item#* }" \
      '{event: "pane_updated", data: {pane: {pane_id: $p, agent: "claude", terminal_title_stripped: $t, revision: 1}}}' >>"$file"
  done
}

# Print the nc processes and the event folders that a name listener of the test left.
name_listener_leftovers() {
  pgrep -f "$BATS_TEST_DIRNAME/fake-nc" || true
  find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'herdr-agent-name.*' 2>/dev/null
}

@test "a title change of a claude renames its agent at once through the session listener" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  export FAKE_TITLE="Postgres port issue" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
  [ "$(grep -c '^agent | get | w1:p5$' "$FAKE_LOG")" -eq 1 ]
  grep -q '"pane.updated"' "$FAKE_LOG.nc"
}

@test "the name listener names a claude that changed its title before the subscription" {
  name_listener "$BATS_TEST_TMPDIR/ev1"
  export FAKE_TITLE="Postgres port issue" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w1:p5","agent":"claude"},{"pane_id":"w1:p6","agent":"codex"}]}}'
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
  [ "$(grep -c '^agent | get | w1:p6$' "$FAKE_LOG")" -eq 0 ]
}

@test "the name listener does not rename when the name already matches" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  export FAKE_TITLE="Postgres port issue" FAKE_NAME=postgres-port-issue-2 FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get | w1:p5$' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c '^agent | rename' "$FAKE_LOG")" -eq 0 ]
}

@test "the name listener keeps the name from herdr agent start" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Ansible role for weekly"
  export FAKE_TITLE="Ansible role for weekly" FAKE_NAME=repo-scout FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | rename' "$FAKE_LOG")" -eq 0 ]
}

@test "the name listener renames a claude that still has its start name" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  export FAKE_TITLE="Postgres port issue" FAKE_NAME=claude-start-w1-p5 FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
}

@test "the name listener follows a new title after /rename of a name that it gave" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 db-migration-fix"
  printf 'w1:p5 postgres-port-issue\n' >"$BATS_TEST_TMPDIR/herdr-agent-name-session-default.names"
  export FAKE_TITLE="db-migration-fix" FAKE_NAME=postgres-port-issue FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | db-migration-fix' "$FAKE_LOG"
  grep -qx 'w1:p5 db-migration-fix' "$BATS_TEST_TMPDIR/herdr-agent-name-session-default.names"
}

@test "the name listener ignores the title of a pane without claude" {
  name_listener "$BATS_TEST_TMPDIR/ev1"
  printf '%s\n' '{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p6","agent":null,"terminal_title_stripped":"vim"}}}' >"$BATS_TEST_TMPDIR/ev1"
  export FAKE_TITLE="vim" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 0 ]
}

@test "the name listener names a claude that herdr detects late" {
  name_listener "$BATS_TEST_TMPDIR/ev1"
  printf '%s\n' '{"event":"pane_agent_detected","data":{"pane_id":"w1:p5","agent":"claude"}}' >"$BATS_TEST_TMPDIR/ev1"
  export FAKE_TITLE="Postgres port issue" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
}

@test "the name listener forgets the name of a claude that exits" {
  name_listener "$BATS_TEST_TMPDIR/ev1"
  printf 'w1:p5 postgres-port-issue\nw1:p6 other\n' >"$BATS_TEST_TMPDIR/herdr-agent-name-session-default.names"
  printf '%s\n' '{"event":"pane_agent_detected","data":{"pane_id":"w1:p5","agent":"claude","released":true}}' >"$BATS_TEST_TMPDIR/ev1"
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/herdr-agent-name-session-default.names")" = "w1:p6 other" ]
}

@test "a worker at the trust prompt keeps the prompt name only until claude gives a title" {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" FAKE_AGENT_KIND="claude" FAKE_TITLE="claude"
  run bash "$PLUGIN_DIR/new-agent-tab.sh" worker w1:p1 w1 'fix the login'
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | fix-the-login' "$FAKE_LOG"
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p9 Login redirect loop"
  export FAKE_TITLE="Login redirect loop" FAKE_NAME=fix-the-login FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p9 | login-redirect-loop' "$FAKE_LOG"
}

@test "a second claude hook does not start a second name listener" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  export FAKE_TITLE="Postgres port issue" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  exec 8>>"$BATS_TEST_TMPDIR/herdr-agent-name-session-default.lock"
  flock -n 8
  run timeout 5 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  exec 8>&-
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_LOG.nc" ]
  [ ! -s "$FAKE_LOG" ]
}

@test "the name hook starts the session listener in the background" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  export HERDR_ENV=1 XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  # One agent get only: a poll loop, after a failure of the events, then stops.
  export FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run bash "$PLUGIN_DIR/sync-name.sh" start <<<'{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  for _ in $(seq 50); do
    grep -q '^agent | rename | w1:p5' "$FAKE_LOG" && break
    sleep 0.1
  done
  grep -qx 'agent | rename | w1:p5 | postgres-port-issue' "$FAKE_LOG"
  grep -q '"pane.updated"' "$FAKE_LOG.nc"
  for _ in $(seq 50); do
    [ -z "$(name_listener_leftovers)" ] && break
    sleep 0.1
  done
}

@test "the name hook falls back to the poll when nc is missing" {
  export HERDR_ENV=1 XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export DISPATCH_NC="$BATS_TEST_TMPDIR/no-nc" FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  run bash "$PLUGIN_DIR/sync-name.sh" start <<<'{"hook_event_name":"SessionStart"}'
  [ "$status" -eq 0 ]
  for _ in $(seq 50); do
    grep -q '^agent | rename | w1:p1' "$FAKE_LOG" && break
    sleep 0.1
  done
  grep -qx 'agent | rename | w1:p1 | postgres-port-issue' "$FAKE_LOG"
  [ ! -e "$BATS_TEST_TMPDIR/herdr-agent-name-session-default.lock" ]
}

@test "the name listener falls back to the poll of its pane when the subscription fails" {
  name_listener "$BATS_TEST_TMPDIR/ev1"
  printf '%s\n' '{"id":"x","error":{"code":"internal_error"}}' >"$BATS_TEST_TMPDIR/err"
  # The fake nc prints the reply first: an error reply needs its own nc.
  cat >"$BATS_TEST_TMPDIR/nc" <<NC
#!/usr/bin/env bash
read -r request
printf '%s\n' "\$request" >>"$FAKE_LOG.nc"
cat "$BATS_TEST_TMPDIR/err"
NC
  chmod +x "$BATS_TEST_TMPDIR/nc"
  export DISPATCH_NC="$BATS_TEST_TMPDIR/nc" FAKE_TITLE="Postgres port issue" FAKE_AGENT_GETS=1 AGENT_TABS_SYNC_INTERVAL=0
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'agent | rename | w1:p1 | postgres-port-issue' "$FAKE_LOG"
  # The poll gives the lock free: the hook of the next claude tries the events again.
  exec 8>>"$BATS_TEST_TMPDIR/herdr-agent-name-session-default.lock"
  flock -n 8
  exec 8>&-
}

@test "the name listener stops when the session stops" {
  name_listener "$BATS_TEST_TMPDIR/ev1"
  # The fake nc marks the session as stopped and closes the connection.
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_LOG.nc")" -eq 1 ]
  # The lock is free: the hook of the next claude in a new session starts a listener.
  exec 8>>"$BATS_TEST_TMPDIR/herdr-agent-name-session-default.lock"
  flock -n 8
  exec 8>&-
}

@test "the name listener leaves no nc process and no fifo behind" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  : >"$BATS_TEST_TMPDIR/ev2"
  export FAKE_TITLE="Postgres port issue" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1 $BATS_TEST_TMPDIR/ev2"
  # A signal stops the listener while nc keeps the connection.
  bash "$PLUGIN_DIR/sync-name.sh" listen w1:p1 &
  pid=$!
  for _ in $(seq 50); do
    grep -q '^agent | rename | w1:p5' "$FAKE_LOG" && break
    sleep 0.1
  done
  grep -q '^agent | rename | w1:p5' "$FAKE_LOG"
  sleep 1.5
  kill "$pid"
  wait "$pid" || true
  sleep 0.3
  [ -z "$(name_listener_leftovers)" ]
}

@test "the name listener restarts with new code" {
  name_listener "$BATS_TEST_TMPDIR/ev1" "w1:p5 Postgres port issue"
  : >"$BATS_TEST_TMPDIR/ev2"
  cp -R "$PLUGIN_DIR" "$BATS_TEST_TMPDIR/plugin"
  cat >"$BATS_TEST_TMPDIR/nc" <<EOF2
#!/usr/bin/env bash
if [ ! -e "$BATS_TEST_TMPDIR/changed" ]; then
  : >"$BATS_TEST_TMPDIR/changed"
  printf 'sync_pane_name() { echo "\$1" >>"$BATS_TEST_TMPDIR/new-code"; }\n' >>"$BATS_TEST_TMPDIR/plugin/lib.sh"
fi
exec "$BATS_TEST_DIRNAME/fake-nc" "\$@"
EOF2
  chmod +x "$BATS_TEST_TMPDIR/nc"
  printf '%s\n' '{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p7","agent":"claude","terminal_title_stripped":"Other"}}}' >"$BATS_TEST_TMPDIR/ev2"
  export DISPATCH_NC="$BATS_TEST_TMPDIR/nc" FAKE_TITLE="Postgres port issue" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1 $BATS_TEST_TMPDIR/ev2"
  run timeout 10 bash "$BATS_TEST_TMPDIR/plugin/sync-name.sh" listen w1:p1
  [ "$status" -eq 0 ]
  grep -qx 'w1:p7' "$BATS_TEST_TMPDIR/new-code"
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

# Make pane w1:p1 a view of the worker pane w9:p1 of the hidden session.
view_of_worker() {
  printf '%s' "$HERDR_BIN_PATH --session board-workers agent attach w9:p1" >"$FAKE_LOG.run.w1:p1"
}

@test "reviewr in a worker view opens reviewr for the recorded worktree of the worker" {
  make_repo >/dev/null
  worktree=$(make_worktree)
  mkdir -p "$(dirname "$(wt_file)")"
  printf '%s\n' "$worktree" >"$(dirname "$(wt_file)")/board-workers.w9_p1"
  view_of_worker
  export FAKE_CWD="$HOME"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q "^plugin | pane | open | .* | --target-pane | w1:p1 | .* | --cwd | $worktree | --focus$" "$FAKE_LOG"
}

@test "reviewr in a worker view uses the cwd of the worker without a record" {
  root=$(make_repo)
  view_of_worker
  export FAKE_CWD="$HOME" FAKE_HIDDEN_CWD="$root/src"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q "^plugin | pane | open | .* | --cwd | $root | --focus$" "$FAKE_LOG"
}

@test "reviewr in a worker view does not use the record of the same pane ID in the default session" {
  root=$(make_repo)
  worktree=$(make_worktree)
  mkdir -p "$(dirname "$(wt_file)")"
  printf '%s\n' "$worktree" >"$(dirname "$(wt_file)")/w9_p1"
  view_of_worker
  export FAKE_CWD="$HOME" FAKE_HIDDEN_CWD="$root"
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  grep -q "^plugin | pane | open | .* | --cwd | $root | --focus$" "$FAKE_LOG"
}

@test "split in a worker view opens the new pane in the recorded worktree of the worker" {
  make_repo >/dev/null
  worktree=$(make_worktree)
  mkdir -p "$(dirname "$(wt_file)")"
  printf '%s\n' "$worktree" >"$(dirname "$(wt_file)")/board-workers.w9_p1"
  view_of_worker
  export FAKE_CWD="$HOME"
  run bash "$PLUGIN_DIR/split.sh" right
  [ "$status" -eq 0 ]
  grep -qx "pane | split | w1:p1 | --direction | right | --cwd | $worktree | --focus" "$FAKE_LOG"
}

@test "split in a worker view uses the cwd of the worker without a record" {
  root=$(make_repo)
  view_of_worker
  export FAKE_CWD="$HOME" FAKE_HIDDEN_CWD="$root/src"
  run bash "$PLUGIN_DIR/split.sh" down
  [ "$status" -eq 0 ]
  grep -qx "pane | split | w1:p1 | --direction | down | --cwd | $root/src | --focus" "$FAKE_LOG"
}

@test "split in another pane keeps the folder that Herdr gives" {
  export FAKE_CWD="$HOME"
  run bash "$PLUGIN_DIR/split.sh" down
  [ "$status" -eq 0 ]
  grep -qx 'pane | split | w1:p1 | --direction | down | --focus' "$FAKE_LOG"
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

@test "track-worktree in another Herdr session records the worktree under the session" {
  export HERDR_ENV=1 HERDR_SESSION=board-workers HERDR_PANE_ID=w9:p1 CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR=$(make_repo)
  worktree=$(make_worktree)
  track tool "$(tool_json Edit "{\"file_path\":\"$worktree/src/a.txt\"}" "$CLAUDE_PROJECT_DIR")"
  [ "$status" -eq 0 ]
  [ "$(cat "$(dirname "$(wt_file)")/board-workers.w9_p1")" = "$worktree" ]
  [ ! -e "$(dirname "$(wt_file)")/w9_p1" ]
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

# Run the pre mode of track-worktree for a Bash command $1 of a worker in the hidden session.
worker_pre() {
  export HERDR_ENV=1 HERDR_SESSION=board-workers
  run bash "$PLUGIN_DIR/track-worktree.sh" pre <<<"$(bash_json "$1" "$BATS_TEST_TMPDIR")"
}

@test "a worker in the hidden session cannot open reviewr" {
  worker_pre 'herdr plugin pane open --plugin persiyanov.reviewr --entrypoint pane --placement split --target-pane wG:p1'
  [ "$status" -eq 2 ]
  [[ "$output" == *"hidden Herdr session board-workers"* ]]
}

@test "a worker cannot split its pane" {
  worker_pre 'herdr pane split --current --direction right --cwd "/x"'
  [ "$status" -eq 2 ]
}

@test "a worker cannot start an agent" {
  worker_pre 'cd /tmp && herdr agent start reviewer --kind claude --pane wG:p7'
  [ "$status" -eq 2 ]
}

@test "a worker cannot create a tab with a global option" {
  worker_pre 'herdr --session board-workers tab create'
  [ "$status" -eq 2 ]
  worker_pre 'herdr --session=board-workers --json worktree open x'
  [ "$status" -eq 2 ]
}

@test "a worker can still read a pane and prompt an agent" {
  worker_pre 'herdr pane read wG:p1 --lines 20'
  [ "$status" -eq 0 ]
  worker_pre 'herdr agent prompt wG:p2 "please split the pane"'
  [ "$status" -eq 0 ]
}

@test "a worker in a session set by DISPATCH_SESSION cannot split its pane" {
  export DISPATCH_SESSION=hidden2 HERDR_ENV=1 HERDR_SESSION=hidden2
  run bash "$PLUGIN_DIR/track-worktree.sh" pre <<<"$(bash_json 'herdr pane split --current' "$BATS_TEST_TMPDIR")"
  [ "$status" -eq 2 ]
}

@test "a claude in the user session can split a pane" {
  export HERDR_ENV=1
  run bash "$PLUGIN_DIR/track-worktree.sh" pre <<<"$(bash_json 'herdr pane split --current --direction right' "$BATS_TEST_TMPDIR")"
  [ "$status" -eq 0 ]
}

@test "an Edit tool call of a worker is not blocked" {
  export HERDR_ENV=1 HERDR_SESSION=board-workers
  run bash "$PLUGIN_DIR/track-worktree.sh" pre <<<"$(tool_json Edit '{"file_path":"/x/herdr pane split"}' "$BATS_TEST_TMPDIR")"
  [ "$status" -eq 0 ]
}

@test "a malformed stdin JSON of a worker does not block" {
  export HERDR_ENV=1 HERDR_SESSION=board-workers
  run bash "$PLUGIN_DIR/track-worktree.sh" pre <<<'not json{ herdr pane split'
  [ "$status" -eq 0 ]
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

@test "start_claude passes extra claude arguments after the effort" {
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_claude w1:p9 high --setting-sources user --permission-mode dontAsk"
  [ "$status" -eq 0 ]
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --effort | high | --setting-sources | user | --permission-mode | dontAsk' "$FAKE_LOG"
}

@test "start_claude passes extra claude arguments without an effort" {
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_claude w1:p9 '' --permission-mode dontAsk"
  grep -qx 'agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9 | --timeout | 60000 | -- | --permission-mode | dontAsk' "$FAKE_LOG"
}

@test "start_claude gives the desktop display to the shell of a pane of the hidden session first" {
  export FAKE_SESSION_RUNNING=board-workers
  printf 'DISPLAY=:1\nXAUTHORITY=/run/xauth\nOTHER_DESKTOP=1\n' >"$DISPATCH_DESKTOP_ENVIRON"
  run bash -c "source '$PLUGIN_DIR/lib.sh'; HT=(\"\$H\" --session board-workers); start_claude w1:p9 high"
  [ "$status" -eq 0 ]
  run_line=$(grep -nxF 'board-workers | pane | run | w1:p9 | [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || export DISPLAY=:1 XAUTHORITY=/run/xauth' "$FAKE_SESSION_LOG" | cut -d: -f1)
  start_line=$(grep -n '^board-workers | agent | start | ' "$FAKE_SESSION_LOG" | cut -d: -f1)
  [ -n "$run_line" ]
  [ "$run_line" -lt "$start_line" ]
}

@test "start_claude runs no display command in the session of the user or with no desktop display" {
  printf 'DISPLAY=:1\n' >"$DISPATCH_DESKTOP_ENVIRON"
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_claude w1:p9 high"
  [ "$status" -eq 0 ]
  export FAKE_SESSION_RUNNING=board-workers
  : >"$DISPATCH_DESKTOP_ENVIRON"
  run bash -c "source '$PLUGIN_DIR/lib.sh'; HT=(\"\$H\" --session board-workers); start_claude w1:p9 high"
  [ "$status" -eq 0 ]
  [ "$(grep -c '| pane | run |' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "start_claude waits while the shell of a new tab is not at its prompt yet" {
  export FAKE_START_BUSY=2
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_claude w1:p9 high"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | start | ' "$FAKE_LOG")" -eq 3 ]
}

@test "start_claude gives up when the shell of the pane stays busy" {
  export FAKE_START_BUSY=1000 AGENT_TABS_START_BUSY_WAIT=1
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_claude w1:p9 high"
  [ "$status" -eq 1 ]
  [[ "$output" == *agent_pane_busy* ]]
  [ "$(grep -c '^agent | start | ' "$FAKE_LOG")" -gt 1 ]
  grep -qx 'agent | rename | w1:p9 | --clear' "$FAKE_LOG"
}

@test "start_claude does not retry when claude fails to start for another reason" {
  export FAKE_START_FAIL=1
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_claude w1:p9 high"
  [ "$status" -eq 1 ]
  [[ "$output" == *agent_not_ready* ]]
  [ "$(grep -c '^agent | start | ' "$FAKE_LOG")" -eq 1 ]
}

@test "a worker starts while another worker of the hidden session still starts" {
  export FAKE_SESSION_RUNNING=board-workers
  printf 'w1:p4 claude\nw1:p5 claude-start-w1-p5\n' >"$FAKE_LOG.names.board-workers"
  run bash -c "source '$PLUGIN_DIR/lib.sh'; HT=(\"\$H\" --session board-workers); start_claude w1:p9 high"
  [ "$status" -eq 0 ]
  [[ "$output" != *agent_name_taken* ]]
  grep -q '^board-workers | agent | rename | w1:p9 | --clear$' "$FAKE_SESSION_LOG"
}

@test "2 panes that differ only in the case of a letter start with different names" {
  run bash -c "source '$PLUGIN_DIR/lib.sh'; start_agent_name wB:p4B; start_agent_name wb:p4b"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = claude-start-w_b-p4_b ]
  [ "${lines[1]}" = claude-start-wb-p4b ]
}

@test "vault_path prints OBSIDIAN_VAULT_PATH" {
  OBSIDIAN_VAULT_PATH=/vault run bash -c "source '$PLUGIN_DIR/lib.sh'; vault_path"
  [ "$output" = /vault ]
}

@test "vault_path reads the claude user settings when the variable is empty" {
  mkdir -p "$HOME/.claude"
  printf '{"env":{"OBSIDIAN_VAULT_PATH":"/from/settings"}}\n' >"$HOME/.claude/settings.json"
  OBSIDIAN_VAULT_PATH= run bash -c "source '$PLUGIN_DIR/lib.sh'; vault_path"
  [ "$output" = /from/settings ]
}

@test "vault_path fails when no path is set" {
  OBSIDIAN_VAULT_PATH= run bash -c "source '$PLUGIN_DIR/lib.sh'; vault_path"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a worker is told that the user opens reviewr in its view, not the worker" {
  printf 'Help the user review the branch with reviewr\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"home orchestrator"},{"workspace_id":"w3","label":"home workers"}]}}'
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Review X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q 'Do not open a Herdr pane, tab or plugin pane, for example reviewr' "$FAKE_LOG"
  grep -q 'The user opens reviewr with ctrl+b d in your view.' "$FAKE_LOG"
}

@test "dispatch start task opens a background tab and sends the prompt with the footer" {
  printf 'Fix the "x" in $HOME `now`\nline two\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"home orchestrator"},{"workspace_id":"w3","label":"home workers"}]}}'
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = w1:p9 ]
  [[ "${lines[1]}" == "$HOME/.local/state/board-orchestrator/fix-x-"*.md ]]
  grep -qx "tab | create | --workspace | w3 | --cwd | $BATS_TEST_TMPDIR | --no-focus" "$FAKE_LOG"
  grep -q '^agent | prompt | w1:p9 | Fix the "x" in $HOME `now`' "$FAKE_LOG"
  grep -q 'line two' "$FAKE_LOG"
  grep -q 'Do not merge, deploy or change production.' "$FAKE_LOG"
  grep -q 'Write the report in one Write call, as your last step.' "$FAKE_LOG"
  local rename main
  rename=$(grep -nx 'agent | prompt | w1:p9 | /rename Fix X' "$FAKE_LOG" | cut -d: -f1)
  main=$(grep -n '^agent | prompt | w1:p9 | Fix the "x"' "$FAKE_LOG" | cut -d: -f1)
  [ -n "$rename" ]
  [ -n "$main" ]
  [ "$rename" -lt "$main" ]
  [ "$(grep -c -- '--permission-mode' "$FAKE_LOG")" -eq 0 ]
  grep -q 'Start the report with one line: RESULT: DONE when the work of the card is complete, or RESULT: WAITS FOR USER when the user must act (a PR to review or merge, a question, a decision).' "$FAKE_LOG"
  grep -q 'Do not edit the vault. When the user asks for a change to the board or to a task note, write it in the report under a heading ## Vault changes, one change for each item. For a new task, write only its title, its project, its priority and one context line: the orchestrator writes the card in the board format, so do not read the vault for it. For a change to existing text, give the note path and the exact old and new text.' "$FAKE_LOG"
  grep -q 'When the user answers you or asks for more work after your report, write the full report again when you finish. The new report replaces the old one.' "$FAKE_LOG"
}

@test "dispatch start creates the workers workspace with no focus when it is missing" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"lab orchestrator"}]}}'
  export FAKE_WS_LABEL="lab orchestrator"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR/proj"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR/proj" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = w2:p1 ]
  grep -qx 'workspace | get | w1' "$FAKE_LOG"
  grep -qx "workspace | create | --cwd | $BATS_TEST_TMPDIR/proj | --label | lab workers | --no-focus" "$FAKE_LOG"
  [ "$(grep -c '^tab | create' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c 'focus | ' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c '^pane | move' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start opens a tab in the workers workspace when it exists" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"work orchestrator"},{"workspace_id":"w5","label":"work workers"}]}}'
  export FAKE_WS_LABEL="work orchestrator"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR/proj"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR/proj" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = w1:p9 ]
  grep -qx "tab | create | --workspace | w5 | --cwd | $BATS_TEST_TMPDIR/proj | --no-focus" "$FAKE_LOG"
  [ "$(grep -c '^workspace | create' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c 'focus | ' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c '^pane | move' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start adds workers to a label with no orchestrator suffix" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"home"}]}}'
  export FAKE_WS_LABEL="home"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR/proj"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR/proj" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx "workspace | create | --cwd | $BATS_TEST_TMPDIR/proj | --label | home workers | --no-focus" "$FAKE_LOG"
}

@test "dispatch start rejects an unknown mode" {
  printf 'Do it\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start bogus "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
}

@test "dispatch start task has no disallowed tools" {
  printf 'Do it\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--disallowedTools' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c 'Do not push' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start auto starts claude with the allow list and dontAsk" {
  readonly_list "$BATS_TEST_TMPDIR" '["Read","mcp__demo__query"]'
  printf 'Run the checks\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "Stage 1 checks" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q -- "^agent | start | claude-start-[^ ]* .* -- | --setting-sources | user | --settings | $BATS_TEST_TMPDIR/.claude/settings.readonly.json | --permission-mode | dontAsk" "$FAKE_LOG"
  grep -qE -- '--allowedTools \| Edit\(//[^|]*$' "$FAKE_LOG"
  grep -q '^Read$' "$FAKE_LOG"
  grep -q '^mcp__demo__query$' "$FAKE_LOG"
  grep -q 'STATUS: OK, STATUS: STOP or STATUS: REFUSED' "$FAKE_LOG"
  grep -q 'REFUSED: <command>' "$FAKE_LOG"
  grep -q 'Do not edit the vault. When the user asks for a change to the board or to a task note, write it in the report under a heading ## Vault changes, one change for each item. For a new task, write only its title, its project, its priority and one context line: the orchestrator writes the card in the board format, so do not read the vault for it. For a change to existing text, give the note path and the exact old and new text.' "$FAKE_LOG"
  grep -q 'write the report file with the Edit or Write tool' "$FAKE_LOG"
  grep -q 'Write the report in one Write call, as your last step.' "$FAKE_LOG"
  grep -q 'Do not add another cd or -C, and do not add ; or &&.' "$FAKE_LOG"
  grep -q 'When the user answers you or asks for more work after your report, write the full report again when you finish. The new report replaces the old one.' "$FAKE_LOG"
  [ "$(grep -c 'RESULT:' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start auto tells the worker its allow list" {
  readonly_list "$BATS_TEST_TMPDIR" '["Bash(git status)","mcp__demo__query"]'
  printf 'Run the checks\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "Rules" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q '^Bash(git status)$' "$FAKE_LOG"
  grep -q '^mcp__demo__query$' "$FAKE_LOG"
  grep -q 'Claude refuses all other calls' "$FAKE_LOG"
}

@test "dispatch start auto passes the mcp config when the project has one" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  : >"$BATS_TEST_TMPDIR/proj/.mcp.json"
  readonly_list "$BATS_TEST_TMPDIR/proj" '["Read"]'
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR/proj" "Mcp" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q -- "dontAsk | --mcp-config | $BATS_TEST_TMPDIR/proj/.mcp.json | --allowedTools | Edit(//" "$FAKE_LOG"
}

@test "dispatch start auto without settings.readonly.json opens no tab" {
  printf 'Run the checks\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "Checks" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/.claude/settings.readonly.json"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch start auto with an empty allow list opens no tab" {
  readonly_list "$BATS_TEST_TMPDIR" '[]'
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "C" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"settings.readonly.json"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch start auto with invalid settings.readonly.json opens no tab" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/.claude/settings.readonly.json"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "C" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"settings.readonly.json"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch start auto lists a rule with spaces and brackets on one prompt line" {
  readonly_list "$BATS_TEST_TMPDIR" '["Bash(make check)"]'
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "Rule" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q '^Bash(make check)$' "$FAKE_LOG"
}

@test "dispatch start task with no push policy exits 2 before any herdr call" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no push policy for $BATS_TEST_TMPDIR: run dispatch.sh policy-set"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch start rejects the local mode" {
  allow_push "$BATS_TEST_TMPDIR"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start local "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch start footers repeat no CLAUDE.md rule" {
  allow_push "$BATS_TEST_TMPDIR"
  readonly_list "$BATS_TEST_TMPDIR" '["Read"]'
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "Y" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q 'STATUS: OK' "$FAKE_LOG"
  [ "$(grep -c 'CLAUDE.md' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c 'signature' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch policy is missing when the folder has no settings" {
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = missing ]
}

@test "dispatch policy is allow with a push rule in settings.local.json allow" {
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
}

@test "dispatch policy is ask with a push rule in settings.json ask" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"ask":["Bash(git push origin*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
}

@test "dispatch policy ask wins over allow" {
  allow_push "$BATS_TEST_TMPDIR"
  printf '{"permissions":{"ask":["Bash(git push*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
}

@test "dispatch policy exits 2 for invalid JSON" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"settings.json"* ]]
}

@test "dispatch policy exits 2 when CWD is not a folder" {
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
}

@test "dispatch policy-set allow writes the 11 push rules" {
  forge_remote "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  run jq -r '.permissions.allow[]' "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  [ "${#lines[@]}" -eq 11 ]
  [ "${lines[0]}" = 'Bash(git push*)' ]
  grep -qF 'Bash(gh pr ready*)' "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  [ "$(jq '.permissions.allow | index("Bash(gh pr close*)") != null' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = true ]
  [ "$(jq -r '.permissions.allow[]' "$BATS_TEST_TMPDIR/.claude/settings.local.json" | grep -c 'merge')" -eq 0 ]
}

@test "dispatch policy-set allow and ask deny the 4 merge rules once and keep other deny entries" {
  forge_remote "$BATS_TEST_TMPDIR"
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json" kind
  for kind in allow ask; do
    rm -rf "$BATS_TEST_TMPDIR/.claude"
    mkdir -p "$BATS_TEST_TMPDIR/.claude"
    printf '{"permissions":{"deny":["Bash(rm -rf*)"]}}\n' >"$f"
    run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" "$kind"
    [ "$status" -eq 0 ]
    [ "$output" = "$kind" ]
    run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" "$kind"
    [ "$status" -eq 0 ]
    [ "$output" = "$kind" ]
    run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
    [ "$output" = "$kind" ]
    [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(rm -rf*)","Bash(gh pr merge*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
  done
}

@test "dispatch policy-set removes the old wide forge rules and keeps other rules" {
  forge_remote "$BATS_TEST_TMPDIR"
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Read","Bash(gh pr merge*)","Bash(gh release*)","Bash(gh api -X*)"],"ask":["Bash(gh pr review*)","Bash(make*)"]}}\n' >"$f"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$(jq -r '.permissions.allow[0]' "$f")" = Read ]
  [ "$(jq '.permissions.allow | length' "$f")" -eq 12 ]
  [ "$(jq -c '.permissions.ask' "$f")" = '["Bash(make*)"]' ]
  [ "$(jq -r '.permissions.allow[], .permissions.ask[]' "$f" | grep -cE 'merge|release|api -X|review')" -eq 0 ]
}

@test "dispatch policy-set keeps other keys and entries and adds no duplicate" {
  forge_remote "$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"env":{"A":"1"},"permissions":{"allow":["Read","Bash(git push*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$(jq -r .env.A "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 1 ]
  [ "$(jq -r '.permissions.allow[0]' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = Read ]
  [ "$(jq '.permissions.allow | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 12 ]
}

@test "dispatch policy-set ask writes under ask" {
  forge_remote "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  [ "$(jq '.permissions.ask | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 11 ]
  [ "$(jq '.permissions.allow // [] | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 0 ]
}

@test "dispatch policy-set allow after ask moves the push rules to allow, and ask after allow moves them back" {
  forge_remote "$BATS_TEST_TMPDIR"
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Read"],"ask":["Bash(make*)"],"deny":["Bash(rm -rf*)"]}}\n' >"$f"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$output" = ask ]
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq -c '.permissions.ask' "$f")" = '["Bash(make*)"]' ]
  [ "$(jq '.permissions.allow | length' "$f")" -eq 12 ]
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  [ "$(jq -c '.permissions.allow' "$f")" = '["Read"]' ]
  [ "$(jq '.permissions.ask | length' "$f")" -eq 12 ]
  [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(rm -rf*)","Bash(gh pr merge*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
}

@test "dispatch policy-set allow on a Forgejo remote writes the Forgejo rules and removes only the gh rules of policy-set" {
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  forge_remote "$BATS_TEST_TMPDIR" ssh://forgejo@git.example.org:2222/o/r.git
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Read","Bash(gh api repos/x/*)","Bash(gh pr create*)","Bash(gh pr merge*)"],"ask":["Bash(gh issue edit*)"],"deny":["Bash(gh repo delete*)","Bash(gh pr merge*)"]}}\n' >"$f"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq -c '.permissions.allow' "$f")" = '["Read","Bash(gh api repos/x/*)","Bash(git push*)","Bash(git -C * push*)","Bash(git -c * push*)","mcp__forgejo__create_pull_request","mcp__forgejo__update_pull_request","mcp__forgejo__create_issue","mcp__forgejo__update_issue","mcp__forgejo__create_issue_comment","mcp__forgejo__edit_issue_comment","mcp__forgejo__issue_state_change"]' ]
  [ "$(jq -c '.permissions.ask' "$f")" = '[]' ]
  [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(gh repo delete*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
  [ "$(grep -cE 'gh pr|gh issue' "$f")" -eq 0 ]
}

@test "dispatch policy-set with no remote writes the Forgejo rules" {
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Bash(gh api repos/x/*)","Bash(gh pr create*)"],"deny":["Bash(gh repo delete*)"]}}\n' >"$f"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq '.permissions.allow | length' "$f")" -eq 11 ]
  [ "$(jq -r '.permissions.allow[0]' "$f")" = 'Bash(gh api repos/x/*)' ]
  [ "$(jq '.permissions.allow | index("mcp__forgejo__issue_state_change") != null' "$f")" = true ]
  [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(gh repo delete*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
  [ "$(grep -c 'gh pr' "$f")" -eq 0 ]
}

@test "dispatch policy-set gives GitHub for the https and scp forms of github.com" {
  local url f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  for url in https://github.com/o/r.git git@github.com:o/r.git; do
    rm -rf "$BATS_TEST_TMPDIR/.claude" "$BATS_TEST_TMPDIR/.git"
    forge_remote "$BATS_TEST_TMPDIR" "$url"
    run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
    [ "$status" -eq 0 ]
    [ "$(jq '.permissions.allow | index("Bash(gh pr create*)") != null' "$f")" = true ]
    [ "$(grep -c 'mcp__forgejo__create' "$f")" -eq 0 ]
  done
}

@test "dispatch policy-set ask on a Forgejo remote writes under ask and adds no duplicate" {
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  forge_remote "$BATS_TEST_TMPDIR" ssh://forgejo@git.example.org:2222/o/r.git
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  [ "$(jq '.permissions.ask | length' "$f")" -eq 10 ]
  [ "$(jq '.permissions.ask | index("mcp__forgejo__create_pull_request") != null' "$f")" = true ]
  [ "$(jq '.permissions.allow // [] | length' "$f")" -eq 0 ]
  [ "$(jq '.permissions.deny | length' "$f")" -eq 3 ]
}

@test "dispatch policy-set refuses a bad mode and invalid JSON" {
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" deny
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/.claude/settings.local.json" ]
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = '{bad' ]
}

@test "dispatch start fails when claude does not start" {
  export FAKE_START_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Claude did not start in the new tab."* ]]
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start prints the pane on exit 1 when claude does not start in it" {
  export FAKE_START_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = w2:p1 ]
}

@test "dispatch start prints the pane on exit 1 when the prompt fails" {
  export FAKE_FINAL_PROMPT_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = w2:p1 ]
}

@test "dispatch wait returns 0 when the report exists" {
  export FAKE_AGENT_KIND=claude DISPATCH_POLL=0
  printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/r.md"
  run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
}

@test "dispatch wait returns 1 when the agent is gone and no report exists" {
  export DISPATCH_POLL=0
  run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the agent in w1:p9 stopped with no report"* ]]
}

@test "dispatch.sh runs through its skill link" {
  export DISPATCH_POLL=0
  printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/r.md"
  run bash "$PLUGIN_DIR/../../../claude/skills/board-orchestrator/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
}

@test "dispatch wait returns 0 when the report appears as the agent exits" {
  export DISPATCH_POLL=0
  cat >"$BATS_TEST_TMPDIR/herdr-late" <<EOS
#!/usr/bin/env bash
printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/late.md"
exit 1
EOS
  chmod +x "$BATS_TEST_TMPDIR/herdr-late"
  HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr-late" run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/late.md"
  [ "$status" -eq 0 ]
}

@test "dispatch wait asks 3 times before it decides the agent is gone" {
  export DISPATCH_POLL=0
  run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
}

@test "dispatch start gives two workers with the same name different reports" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Same" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  first="${lines[1]}"
  [ -n "$first" ]
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Same" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ -n "${lines[1]}" ]
  [ "$first" != "${lines[1]}" ]
  [[ "$first" == */same-* ]]
}

@test "dispatch start without a workspace exits 2 before any herdr call" {
  unset HERDR_WORKSPACE_ID
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
  [ ! -e "$HOME/.local/state/board-orchestrator" ]
}

@test "dispatch start exits 2 before any herdr call when CWD is not a folder" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR/missing" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a folder"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch wait keeps waiting while the report is empty" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  : >"$BATS_TEST_TMPDIR/empty.md"
  run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/empty.md"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 5 ]
}

@test "board open opens the board popup" {
  run bash "$PLUGIN_DIR/board.sh" open
  [ "$status" -eq 0 ]
  grep -qx 'plugin | pane | open | --plugin | awea.agent-tabs | --entrypoint | board-prompt' "$FAKE_LOG"
}

@test "board open shows a notification when no pane has focus" {
  unset HERDR_PANE_ID
  run bash "$PLUGIN_DIR/board.sh" open
  [ "$status" -eq 1 ]
  grep -q '^notification | show' "$FAKE_LOG"
  [ "$(grep -c '^plugin | pane | open' "$FAKE_LOG")" -eq 0 ]
}

@test "board prompt lists only kanban boards and starts the worker for the key" {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault" HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  printf -- '---\n\nkanban-plugin: board\n\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/home.md"
  printf -- '---\n\nkanban-plugin: board\n\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/work.md"
  printf '# rules\n' >"$OBSIDIAN_VAULT_PATH/Boards/_CLAUDE.md"
  run_in_tty "bash '$PLUGIN_DIR/board.sh' prompt" '2'
  [[ "$output" == *"[1] home"*"[2] work"* ]]
  [[ "$output" != *_CLAUDE* ]]
  for _ in $(seq 50); do
    grep -q '^agent | prompt | w2:p1 | /board-orchestrator work$' "$FAKE_LOG" && break
    sleep 0.1
  done
  grep -q '^agent | prompt | w2:p1 | /board-orchestrator work$' "$FAKE_LOG"
}

@test "board prompt starts the worker on macOS" {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault" HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  printf -- 'kanban-plugin: board\n' >"$OBSIDIAN_VAULT_PATH/Boards/home.md"
  as_macos
  run_in_tty "bash '$PLUGIN_DIR/board.sh' prompt" '1'
  for _ in $(seq 50); do
    grep -q '^agent | prompt | w2:p1 | /board-orchestrator home$' "$FAKE_LOG" && break
    sleep 0.1
  done
  grep -q '^agent | prompt | w2:p1 | /board-orchestrator home$' "$FAKE_LOG"
}

@test "board prompt starts no worker after Esc" {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault" HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  printf -- 'kanban-plugin: board\n' >"$OBSIDIAN_VAULT_PATH/Boards/home.md"
  run_in_tty "bash '$PLUGIN_DIR/board.sh' prompt" '\e'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1] home"* ]]
  sleep 0.5
  [ "$(grep -c '^tab | create\|^agent' "$FAKE_LOG")" -eq 0 ]
}

@test "board prompt cancels on end of input" {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault" HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  printf -- 'kanban-plugin: board\n' >"$OBSIDIAN_VAULT_PATH/Boards/home.md"
  run timeout 5 bash "$PLUGIN_DIR/board.sh" prompt </dev/null
  [ "$status" -eq 0 ]
  [ "$(grep -c '^tab | create' "$FAKE_LOG")" -eq 0 ]
}

@test "board prompt with no board tells the user also with no debug file" {
  rm "$HERDR_PLUGIN_CONFIG_DIR/debug"
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  run timeout 5 bash "$PLUGIN_DIR/board.sh" prompt </dev/null
  [ "$status" -eq 1 ]
  grep -q "^notification | show | Agent tabs | --body | No board in $OBSIDIAN_VAULT_PATH/Boards" "$FAKE_LOG"
}

@test "board worker starts the orchestrator in a workspace of the user in the vault folder" {
  export FAKE_DEFAULT_WS_ROOT=w3:p1
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  local toast create start rename main
  toast=$(grep -n '^default | notification | show | Agent tabs | --body | Starting the orchestrator of the board work' "$FAKE_SESSION_LOG" | cut -d: -f1)
  create=$(grep -nx 'default | workspace | create | --cwd | /vault | --label | work orchestrator | --focus' "$FAKE_SESSION_LOG" | cut -d: -f1)
  start=$(grep -n '^default | agent | start | claude-start-w3-p1 | --kind | claude | --pane | w3:p1 .*-- | --effort | high' "$FAKE_SESSION_LOG" | cut -d: -f1)
  [ -n "$toast" ] && [ -n "$create" ] && [ -n "$start" ]
  [ "$toast" -lt "$create" ]
  [ "$create" -lt "$start" ]
  rename=$(grep -nx 'default | agent | prompt | w3:p1 | /rename work-orchestrator' "$FAKE_SESSION_LOG" | cut -d: -f1)
  main=$(grep -nx 'default | agent | prompt | w3:p1 | /board-orchestrator work' "$FAKE_SESSION_LOG" | cut -d: -f1)
  [ -n "$rename" ] && [ -n "$main" ]
  [ "$rename" -lt "$main" ]
  grep -qx 'default | agent | rename | w3:p1 | work-orchestrator' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^board-workers | \(workspace | create\|tab | create\|agent | start\|agent | prompt\)' "$FAKE_SESSION_LOG")" -eq 0 ]
  [ "$(grep -c '| pane | run' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "board worker waits for the answer at a start question, then sends the board command" {
  export FAKE_DEFAULT_WS_ROOT=w3:p1 FAKE_START_FAIL=1
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  grep -qx 'default | agent | wait | w3:p1 | --until | idle | --until | done | --timeout | 600000' "$FAKE_SESSION_LOG"
  grep -qx 'default | agent | prompt | w3:p1 | /board-orchestrator work' "$FAKE_SESSION_LOG"
}

@test "board worker starts nothing with no vault path" {
  OBSIDIAN_VAULT_PATH= run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 1 ]
  [ "$(grep -c '^workspace | create\|^agent | start' "$FAKE_LOG")" -eq 0 ]
}

@test "board worker starts nothing when the lookup of the user workspaces fails" {
  export FAKE_WORKSPACE_LIST_FAIL=1
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tab | create\|^workspace | create\|^agent | start\|^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "board worker focuses the orchestrator that runs for the board and starts none" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w26","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w26:p1","workspace_id":"w26"}]}}'
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[]}}' FAKE_HIDDEN_AGENTS_JSON='{"result":{"agents":[]}}'
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  grep -qx 'default | workspace | focus | w26' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^agent | start\|^agent | prompt\|^tab | create\|^workspace | create\|^pane | run' "$FAKE_LOG")" -eq 0 ]
}

@test "views-restore closes the bare shell tabs of an orchestrator workspace and opens the views of live workers" {
  restore_board
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | tab | close' "$FAKE_SESSION_LOG")" -eq 1 ]
  grep -qx 'default | tab | create | --workspace | w1 | --label | worker | --no-focus' "$FAKE_SESSION_LOG"
  grep -qx "default | pane | run | w1:p5 | $HERDR_BIN_PATH --session board-workers agent attach w9:p3" "$FAKE_SESSION_LOG"
  [ "$(grep -c ' | focus\|--focus' "$FAKE_LOG")" -eq 0 ]
}

@test "views-restore keeps a tab that has a program other than a shell" {
  restore_board
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"},{"pane_id":"w1:p7","tab_id":"w1:t5"},{"pane_id":"w1:p8","tab_id":"w1:t5"}]}}'
  export FAKE_REVIEWR_PANES=w1:p8
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | tab | close' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -q '^default | tab | create' "$FAKE_SESSION_LOG"
}

@test "views-restore never closes the orchestrator tab, also when its pane shows a shell" {
  restore_board
  export FAKE_SHELL_PANES="w1:p1 w1:p7"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  ! grep -qx 'default | tab | close | w1:t1' "$FAKE_SESSION_LOG"
}

@test "views-restore changes nothing for a worker with a valid view, on a second run" {
  restore_board
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  export FAKE_TABS_JSON='{"result":{"tabs":[{"tab_id":"w1:t1"},{"tab_id":"w1:t5"}]}}'
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"},{"pane_id":"w1:p5","tab_id":"w1:t5"}]}}'
  export FAKE_SHELL_PANES=""
  : >"$FAKE_SESSION_LOG"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | tab | close\|^default | tab | create\|^default | pane | run' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "views-restore skips a worker whose pane has no claude" {
  restore_board
  unset FAKE_AGENT_KIND
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | tab | close\|^default | tab | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "views-restore skips a board that has no orchestrator workspace" {
  restore_board
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w2","label":"other orchestrator"}]}}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | tab | close\|^default | tab | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "views-restore exits 0 and changes nothing when the hidden session does not answer" {
  restore_board
  export FAKE_SESSION_RUNNING=""
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | tab | close\|^default | tab | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "views-restore with no workers file exits 0 with no Herdr call" {
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" views-restore
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "the startup hook returns at once and restores the views detached" {
  restore_board
  export DISPATCH_RESTORE_POLL=1 DISPATCH_RESTORE_WAIT=0
  start=$SECONDS
  run --separate-stderr bash "$PLUGIN_DIR/startup.sh"
  [ "$status" -eq 0 ]
  [ $((SECONDS - start)) -lt 3 ]
  for _ in $(seq 100); do
    grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG" && break
    sleep 0.1
  done
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
}

@test "the startup hook does not wait for a hidden session that is late" {
  restore_board
  export FAKE_SESSION_RUNNING="" DISPATCH_RESTORE_POLL=1 DISPATCH_RESTORE_WAIT=30
  start=$SECONDS
  run --separate-stderr bash "$PLUGIN_DIR/startup.sh"
  [ "$status" -eq 0 ]
  [ $((SECONDS - start)) -lt 3 ]
  # The restore works after the hidden session answers.
  printf board-workers >"$FAKE_LOG.running"
  for _ in $(seq 100); do
    grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG" && break
    sleep 0.1
  done
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
}

@test "the manifest declares the startup hook" {
  grep -qx '\[\[startup\]\]' "$PLUGIN_DIR/herdr-plugin.toml"
  grep -qx 'command = \["bash", "startup.sh"\]' "$PLUGIN_DIR/herdr-plugin.toml"
  [ -f "$PLUGIN_DIR/startup.sh" ]
}

@test "board worker restores the views when it focuses the orchestrator that runs" {
  restore_board
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker home
  [ "$status" -eq 0 ]
  for _ in $(seq 100); do
    grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG" && break
    sleep 0.1
  done
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
  grep -qx 'default | workspace | focus | w1' "$FAKE_SESSION_LOG"
}

# Wait until the file $1 has a line that matches the grep pattern $2 (10 seconds at most).
wait_for_line() {
  for _ in $(seq 100); do
    grep -q -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "restart-notice waits for the orchestrator to be idle, then prompts it once with the board name" {
  restore_board
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" restart-notice
  [ "$status" -eq 0 ]
  wait_for_line "$FAKE_SESSION_LOG" '^default | agent | prompt | w1:p1 | '
  grep -q '^default | agent | wait | w1:p1 | --until | idle | --until | done | --timeout | 300000$' "$FAKE_SESSION_LOG"
  [ "$(grep -n '^default | agent | wait | w1:p1' "$FAKE_SESSION_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n '^default | agent | prompt | w1:p1' "$FAKE_SESSION_LOG" | head -1 | cut -d: -f1)" ]
  grep -q 'dispatch.sh workers home, then handle each worker as in rules 6 and 7' "$FAKE_SESSION_LOG"
  grep -q '^default | agent | prompt | w1:p1 | Herdr restarted, so your background wait and watch commands stopped\. Run bash ~/.claude/skills/board-orchestrator/dispatch.sh workers home' "$FAKE_SESSION_LOG"
  sleep 0.5
  [ "$(grep -c '^default | agent | prompt' "$FAKE_SESSION_LOG")" -eq 1 ]
}

@test "restart-notice skips an orchestrator that is not idle in time and logs one line" {
  restore_board
  export FAKE_WAIT_FAIL=1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" restart-notice
  [ "$status" -eq 0 ]
  wait_for_line "$HERDR_PLUGIN_STATE_DIR/board.log" 'restart-notice: .*home.*w1:p1'
  [ "$(grep -c '^default | agent | prompt' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "restart-notice logs one line and moves on when the prompt is rejected" {
  restore_board
  export FAKE_PROMPT_FAIL=1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" restart-notice
  [ "$status" -eq 0 ]
  wait_for_line "$HERDR_PLUGIN_STATE_DIR/board.log" 'restart-notice: .*home.*w1:p1'
  [ "$(grep -c '^default | agent | prompt' "$FAKE_SESSION_LOG")" -eq 1 ]
}

@test "restart-notice prompts nothing when no orchestrator runs" {
  restore_board
  export FAKE_AGENTS_JSON='{"result":{"agents":[]}}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" restart-notice
  [ "$status" -eq 0 ]
  sleep 0.5
  [ "$(grep -c '^default | agent | wait\|^default | agent | prompt' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "restart-notice does nothing in the hidden session" {
  restore_board
  HERDR_SESSION=board-workers run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" restart-notice
  [ "$status" -eq 0 ]
  sleep 0.5
  [ ! -s "$FAKE_LOG" ]
}

@test "the startup hook prompts the orchestrators after the view restore" {
  restore_board
  export DISPATCH_RESTORE_POLL=1 DISPATCH_RESTORE_WAIT=0
  run --separate-stderr bash "$PLUGIN_DIR/startup.sh"
  [ "$status" -eq 0 ]
  wait_for_line "$FAKE_SESSION_LOG" '^default | agent | prompt | w1:p1 | '
  [ "$(grep -n '^default | tab | close | w1:t5' "$FAKE_SESSION_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n '^default | agent | prompt' "$FAKE_SESSION_LOG" | head -1 | cut -d: -f1)" ]
}

@test "views-restore from board worker does not prompt the orchestrator" {
  restore_board
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker home
  [ "$status" -eq 0 ]
  wait_for_line "$FAKE_SESSION_LOG" '^default | tab | close | w1:t5'
  sleep 0.5
  [ "$(grep -c '^default | agent | prompt' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "board worker names the first tab of a new orchestrator workspace orchestrator" {
  export FAKE_DEFAULT_WS_ROOT=w3:p1 FAKE_PANE_TAB=w3:t1
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  grep -qx 'default | tab | rename | w3:t1 | orchestrator' "$FAKE_SESSION_LOG"
}

@test "dispatch start task with invalid settings JSON exits 2 before any herdr call" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch policy is missing with an empty or blank settings file" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  : >"$BATS_TEST_TMPDIR/.claude/settings.json"
  printf '  \n\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = missing ]
}

@test "dispatch policy-set allow on a blank settings.local.json writes the rules" {
  forge_remote "$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '  \n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq '.permissions.allow | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 11 ]
}

@test "dispatch policy and policy-set refuse a file with two JSON documents" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{}\n{}\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = $'{}\n{}' ]
}

@test "dispatch policy is deny with a push rule in deny, and deny wins" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"deny":["Bash(git push*)"],"ask":["Bash(git push*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = deny ]
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
}

@test "dispatch policy-set keeps the file mode, and uses 644 for a new file" {
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$(file_mode "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 644 ]
  chmod 600 "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$(file_mode "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 600 ]
  [ "$(find "$BATS_TEST_TMPDIR/.claude" -name 'settings.local.json.*' | wc -l)" -eq 0 ]
}

@test "dispatch policy-set keeps the file mode on macOS" {
  as_macos
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  chmod 600 "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 600 ]
}

@test "dispatch usage names policy and policy-set" {
  run bash "$PLUGIN_DIR/dispatch.sh" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *policy-set* ]]
  [[ "$output" == *"policy|"* || "$output" == *"policy "* ]]
}

# A fake herdr that runs $1 on each agent get, then finds the agent.
watch_herdr() {
  cat >"$BATS_TEST_TMPDIR/herdr-watch" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FAKE_LOG"
$1
printf '{"result":{"agent":{}}}\n'
EOS
  chmod +x "$BATS_TEST_TMPDIR/herdr-watch"
}

@test "dispatch watch returns 0 when the report changes" {
  export DISPATCH_POLL=0
  printf 'STATUS: STOP\n' >"$BATS_TEST_TMPDIR/r.md"
  watch_herdr "printf 'STATUS: OK\n' >'$BATS_TEST_TMPDIR/r.md'"
  HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr-watch" run bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
}

@test "dispatch watch returns 0 when the report gets the same text with a new mtime" {
  export DISPATCH_POLL=0
  printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/r.md"
  touch -d '2026-01-01 00:00:00' "$BATS_TEST_TMPDIR/r.md"
  watch_herdr "printf 'STATUS: OK\n' >'$BATS_TEST_TMPDIR/r.md'"
  HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr-watch" run bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
}

@test "dispatch watch returns 0 when the report gets the same text with a new mtime on macOS" {
  export DISPATCH_POLL=0
  printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/r.md"
  touch -d '2026-01-01 00:00:00' "$BATS_TEST_TMPDIR/r.md"
  watch_herdr "printf 'STATUS: OK\n' >'$BATS_TEST_TMPDIR/r.md'"
  as_macos
  HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr-watch" run timeout 5 bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
}

@test "dispatch watch keeps watching an unchanged report on macOS" {
  export DISPATCH_POLL=0
  printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/r.md"
  watch_herdr ":"
  as_macos
  HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr-watch" run timeout 2 bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 124 ]
}

@test "dispatch watch returns 1 when the agent is gone and the report did not change" {
  export DISPATCH_POLL=0
  printf 'STATUS: STOP\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the agent in w1:p9 stopped and the report did not change"* ]]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
}

@test "dispatch watch keeps watching while the agent is there" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  printf 'STATUS: STOP\n' >"$BATS_TEST_TMPDIR/r.md"
  run bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 5 ]
}

@test "dispatch wait exits 3 with blocked on a blocked agent and shows a notification" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_NAME=fix-x FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = blocked ]
  grep -q '^notification | show | fix-x needs you | --body | .* | --sound | request$' "$FAKE_LOG"
  [ "$(grep -c '^notification | show' "$FAKE_LOG")" -eq 1 ]
}

@test "dispatch wait exits 3 with idle after two idle checks with no report" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="idle working idle done" FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = idle ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 4 ]
  grep -q '^notification | show | w1:p9 needs you | --body | .* | --sound | request$' "$FAKE_LOG"
}

@test "dispatch wait does not exit 3 after one idle check" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="idle working" FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
}

@test "dispatch wait: a report wins over a blocked agent" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  printf 'RESULT: DONE\n' >"$BATS_TEST_TMPDIR/r.md"
  run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait with SEEN blocked does not exit 3 while still blocked" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_AGENT_GETS=3 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  [ "$status" -eq 1 ]
}

@test "dispatch wait with SEEN blocked exits 3 after a working check, then blocked" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="blocked working blocked" FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  [ "$status" -eq 3 ]
  [ "$output" = blocked ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
}

@test "dispatch wait shows a notification on exit 1" {
  export DISPATCH_POLL=0
  run bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
  grep -q '^notification | show | w1:p9 needs you | --body | .* | --sound | request$' "$FAKE_LOG"
  [ "$(grep -c '^notification | show' "$FAKE_LOG")" -eq 1 ]
}

@test "dispatch watch shows no notification on exit 1" {
  export DISPATCH_POLL=0
  printf 'STATUS: STOP\n' >"$BATS_TEST_TMPDIR/r.md"
  run bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait with seq prints the status and the seq on exit 3" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_SEQS=5 FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "blocked 5" ]
}

@test "dispatch wait with SEEN blocked and a new seq exits 3 for a new prompt" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_SEQS="5 7" FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked 5
  [ "$status" -eq 3 ]
  [ "$output" = "blocked 7" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 2 ]
}

@test "dispatch wait with SEEN blocked and the same seq does not exit 3" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_SEQS=5 FAKE_AGENT_GETS=3 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked 5
  [ "$status" -eq 1 ]
}

@test "dispatch wait exits 3 idle only after two idle checks with the same completion seq" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS="3 4" FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle 4" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
}

@test "dispatch wait with SEEN idle and the same seq does not exit 3" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4 FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle 4
  [ "$status" -eq 1 ]
}

@test "dispatch wait with SEEN blocked exits 3 after an idle check, then blocked" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="blocked idle blocked" FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  [ "$status" -eq 3 ]
  [ "$output" = blocked ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
}

@test "dispatch wait with SEEN idle does not exit 3 while still idle" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle
  [ "$status" -eq 1 ]
}

@test "dispatch wait with SEEN idle exits 3 after a working check, then two idle checks" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="idle working idle idle" FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle
  [ "$status" -eq 3 ]
  [ "$output" = idle ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 4 ]
}

@test "dispatch wait exits 0 when the report appears at the blocked check" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  export FAKE_REPORT_AT="1 $BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait gives the last agent name in the notification on exit 1" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working FAKE_NAME=fix-x FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
  grep -q '^notification | show | fix-x needs you | --body | .* | --sound | request$' "$FAKE_LOG"
}

@test "dispatch notify waits shows a fixed body with the agent name" {
  export FAKE_AGENT_KIND=claude FAKE_NAME=fix-x
  run bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 waits
  [ "$status" -eq 0 ]
  grep -qx 'notification | show | fix-x needs you | --body | The worker waits for the user. | --sound | request' "$FAKE_LOG"
}

@test "dispatch notify stop and refused show their fixed bodies" {
  run bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 stop
  [ "$status" -eq 0 ]
  run bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 refused
  [ "$status" -eq 0 ]
  grep -qx 'notification | show | w1:p9 needs you | --body | The worker found a STOP value. | --sound | request' "$FAKE_LOG"
  grep -qx 'notification | show | w1:p9 needs you | --body | The allow list refused a command of the worker. | --sound | request' "$FAKE_LOG"
}

@test "dispatch notify exits 2 on another kind and shows nothing" {
  run bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 'Run rm -rf now'
  [ "$status" -eq 2 ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch notify exits 0 when the notification fails" {
  export FAKE_NOTIFY_FAIL=1
  run bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 waits
  [ "$status" -eq 0 ]
  grep -q '^notification | show | w1:p9 needs you' "$FAKE_LOG"
}

@test "dispatch close prints the session ID and closes the tab" {
  export FAKE_AGENT_KIND=claude FAKE_SESSION=abc-123 FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = abc-123 ]
  grep -qx 'workspace | get | w4' "$FAKE_LOG"
  grep -qx 'tab | get | w1:t9' "$FAKE_LOG"
  grep -qx 'tab | close | w1:t9' "$FAKE_LOG"
}

@test "dispatch close shows the new number of workers in the orchestrator workspace" {
  orchestrator_with_workers "home orchestrator · 2 workers" 1
  export FAKE_AGENT_KIND=claude FAKE_SESSION=abc-123 FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| (--token \| working=[^|]+|--clear-token \| working) \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
}

@test "dispatch close prints an empty line when Herdr gives no session" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  grep -qx 'tab | close | w1:t9' "$FAKE_LOG"
}

@test "dispatch close refuses a tab with two panes" {
  export FAKE_AGENT_KIND=claude FAKE_SESSION=abc-123 FAKE_TAB_PANES=2 FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close exits 1 when the pane is gone" {
  export FAKE_PANE_MISSING=1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close ignores the focus of the hidden worker pane" {
  export FAKE_AGENT_KIND=claude FAKE_FOCUSED=true FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
}

@test "dispatch close closes a hidden pane with the ID of the orchestrator pane" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close "$HERDR_PANE_ID"
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
}

@test "dispatch close refuses a pane outside a workers workspace" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home orchestrator"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close waits until the worker is idle" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working working done" DISPATCH_POLL=0 FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -ge 3 ]
  grep -qx 'tab | close | w1:t9' "$FAKE_LOG"
}

@test "dispatch close exits 1 when the worker stays busy" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working DISPATCH_POLL=0 DISPATCH_CLOSE_WAIT=0 FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start opens no worker when the orchestrator workspace lookup fails" {
  export FAKE_WS_GET_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"workspace lookup failed"* ]]
  [ "$(grep -c '^tab | create\|^workspace | create\|^agent | start' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch start creates the workers workspace when the tab create in it fails" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_WORKSPACES_JSON_LATER='{"result":{"workspaces":[]}}'
  export FAKE_TAB_CREATE_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = w2:p1 ]
  grep -qx "workspace | create | --cwd | $BATS_TEST_TMPDIR | --label | home workers | --no-focus" "$FAKE_LOG"
}

@test "dispatch start creates no second workspace when the tab create fails and the workspace is still there" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_TAB_CREATE_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^workspace | create' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait gives the completion seq for the idle need" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=done FAKE_SEQS=9 FAKE_COMPLETION_SEQS=2 FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle 2" ]
}

@test "dispatch wait with SEEN idle does not exit 3 when done turns idle on a view" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="done idle" FAKE_SEQS="5 6" FAKE_COMPLETION_SEQS=2 FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle 2
  [ "$status" -eq 1 ]
}

@test "dispatch close does not sleep past DISPATCH_CLOSE_WAIT" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working DISPATCH_POLL=5 DISPATCH_CLOSE_WAIT=1 FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr timeout 4 bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close stops at DISPATCH_CLOSE_WAIT when the agent of the pane is missing for a short time" {
  export FAKE_WS_LABELS='{"w4":"home workers"}' DISPATCH_POLL=5 DISPATCH_CLOSE_WAIT=1
  run --separate-stderr timeout 4 bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^board-workers | tab | close' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch wait with SEEN idle and no completion seq does not exit 3 when done turns idle" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="done idle" FAKE_SEQS="5 6" FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle 5
  [ "$status" -eq 1 ]
}

# Print the calls in the default session, except the lookup of the orchestrator
# workspace, the session list and the workspace list of the worker count.
default_calls() {
  grep '^default | ' "$FAKE_SESSION_LOG" |
    grep -v -e '^default | workspace | get | w1$' -e '^default | session | list' -e '^default | workspace | list$' || true
}

@test "dispatch start runs all worker calls in the hidden session board-workers" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = w1:p9 ]
  grep -qx 'board-workers | workspace | list' "$FAKE_SESSION_LOG"
  grep -qx "board-workers | tab | create | --workspace | w3 | --cwd | $BATS_TEST_TMPDIR | --no-focus" "$FAKE_SESSION_LOG"
  grep -q '^board-workers | agent | start | claude-start-w1-p9 | --kind | claude | --pane | w1:p9' "$FAKE_SESSION_LOG"
  grep -qx 'board-workers | agent | prompt | w1:p9 | /rename Fix X' "$FAKE_SESSION_LOG"
  grep -qx 'board-workers | agent | rename | w1:p9 | fix-x' "$FAKE_SESSION_LOG"
  [ -z "$(default_calls)" ]
}

@test "dispatch start uses the session of DISPATCH_SESSION" {
  export DISPATCH_SESSION=lab-workers FAKE_SESSION_RUNNING=lab-workers
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q '^lab-workers | agent | start' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^board-workers' "$FAKE_SESSION_LOG")" -eq 0 ]
  [ -z "$(default_calls)" ]
}

@test "dispatch start starts the hidden session with the environment of the default server" {
  export FAKE_SESSION_RUNNING="" CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli HERDR_TAB_ID=w1:t1 KEEP_ME=yes
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = w2:p1 ]
  [ -f "$FAKE_LOG.env" ]
  grep -qx 'ONLY_SERVER=1' "$FAKE_LOG.env"
  grep -qx 'PATH=/usr/bin:/bin' "$FAKE_LOG.env"
  grep -qx 'HERDR_STARTUP_CWD=/srv' "$FAKE_LOG.env"
  [ "$(grep -c '^KEEP_ME\|^CLAUDE\|^HERDR_TAB\|^HERDR_BIN' "$FAKE_LOG.env")" -eq 0 ]
  [ -f "$HOME/.local/state/board-orchestrator/server.log" ]
  local server ws
  server=$(grep -nx 'board-workers | server' "$FAKE_SESSION_LOG" | cut -d: -f1)
  ws=$(grep -n '^board-workers | workspace | create' "$FAKE_SESSION_LOG" | cut -d: -f1)
  [ -n "$server" ]
  [ -n "$ws" ]
  [ "$server" -lt "$ws" ]
}

@test "dispatch start uses a login shell and a small environment when the server environment is missing" {
  export FAKE_SESSION_RUNNING="" CLAUDECODE=1 HERDR_TAB_ID=w1:t1 KEEP_ME=yes SHELL=/bin/sh
  export DISPATCH_SERVER_ENVIRON="$BATS_TEST_TMPDIR/missing"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx "HOME=$HOME" "$FAKE_LOG.env"
  [ "$(grep -c '^KEEP_ME\|^CLAUDE\|^HERDR_\|^ONLY_SERVER' "$FAKE_LOG.env")" -eq 0 ]
}

@test "dispatch start gives the hidden session the display of the desktop when the server has none" {
  export FAKE_SESSION_RUNNING=""
  printf 'DISPLAY=:1\nXAUTHORITY=/run/xauth\nWAYLAND_DISPLAY=wayland-0\nOTHER_DESKTOP=1\n' >"$DISPATCH_DESKTOP_ENVIRON"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx 'DISPLAY=:1' "$FAKE_LOG.env"
  grep -qx 'XAUTHORITY=/run/xauth' "$FAKE_LOG.env"
  grep -qx 'WAYLAND_DISPLAY=wayland-0' "$FAKE_LOG.env"
  grep -qx 'ONLY_SERVER=1' "$FAKE_LOG.env"
  [ "$(grep -c '^OTHER_DESKTOP' "$FAKE_LOG.env")" -eq 0 ]
}

@test "dispatch start keeps the display of the server" {
  export FAKE_SESSION_RUNNING=""
  printf 'DISPLAY=:0\0' >>"$DISPATCH_SERVER_ENVIRON"
  printf 'DISPLAY=:1\nXAUTHORITY=/run/xauth\n' >"$DISPATCH_DESKTOP_ENVIRON"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx 'DISPLAY=:0' "$FAKE_LOG.env"
  [ "$(grep -c '^DISPLAY=:1\|^XAUTHORITY' "$FAKE_LOG.env")" -eq 0 ]
}

@test "dispatch start gives the display of the desktop also with the small environment" {
  export FAKE_SESSION_RUNNING="" SHELL=/bin/sh
  unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
  export DISPATCH_SERVER_ENVIRON="$BATS_TEST_TMPDIR/missing"
  printf 'DISPLAY=:1\nXAUTHORITY=/run/xauth\n' >"$DISPATCH_DESKTOP_ENVIRON"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx 'DISPLAY=:1' "$FAKE_LOG.env"
  grep -qx 'XAUTHORITY=/run/xauth' "$FAKE_LOG.env"
}

@test "dispatch start starts the hidden session on macOS" {
  export FAKE_SESSION_RUNNING=""
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  as_macos
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | server' "$FAKE_SESSION_LOG"
}

@test "dispatch start starts the hidden session through a login shell on macOS" {
  export FAKE_SESSION_RUNNING="" SHELL=/bin/sh
  export DISPATCH_SERVER_ENVIRON="$BATS_TEST_TMPDIR/missing"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  as_macos
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | server' "$FAKE_SESSION_LOG"
}

@test "dispatch start starts a stopped session" {
  export FAKE_SESSION_RUNNING="" FAKE_SESSION_STOPPED=board-workers
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | server' "$FAKE_SESSION_LOG"
}

@test "dispatch start starts no server when the session runs" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c '| server$' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch start clears the views file when it starts the server" {
  export FAKE_SESSION_RUNNING=""
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w1:p9 w1:p5\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/state/board-orchestrator/views-board-workers" ] ||
    [ "$(grep -c 'w1:p9' "$HOME/.local/state/board-orchestrator/views-board-workers")" -eq 0 ]
}

@test "dispatch start exits 1 and opens no worker when the hidden session does not answer" {
  export FAKE_SESSION_RUNNING="" DISPATCH_SESSION_WAIT=1
  # The server gets only the environment of the default server.
  printf 'FAKE_SERVER_DEAD=1\0' >>"$DISPATCH_SERVER_ENVIRON"
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *board-workers* ]]
  [ "$(grep -c '^tab | create\|^workspace | create\|^agent | start' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch show opens a view tab that attaches to the hidden worker" {
  export FAKE_AGENT_KIND=claude FAKE_NAME=fix-x FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w1:p5 ]
  grep -qx 'board-workers | agent | get | w1:p9' "$FAKE_SESSION_LOG"
  grep -qx 'default | tab | create | --workspace | w1 | --label | fix-x | --no-focus' "$FAKE_SESSION_LOG"
  grep -qx "default | pane | run | w1:p5 | $HERDR_BIN_PATH --session board-workers agent attach w1:p9" "$FAKE_SESSION_LOG"
  [ "$(grep -c ' | focus\|--focus' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch show labels the view worker when the agent has no name" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -qx 'default | tab | create | --workspace | w1 | --label | worker | --no-focus' "$FAKE_SESSION_LOG"
}

@test "dispatch show reuses the view of the worker while its pane exists" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  export FAKE_TAB_ROOT=w1:p6
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w1:p5 ]
  [ "$(grep -c '^default | tab | create' "$FAKE_SESSION_LOG")" -eq 1 ]
  grep -qx 'default | pane | get | w1:p5' "$FAKE_SESSION_LOG"
}

@test "dispatch show opens a new view when the old view pane is gone" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  export FAKE_TAB_ROOT=w1:p6 FAKE_PANE_MISSING=1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w1:p6 ]
  [ "$(grep -c '^default | tab | create' "$FAKE_SESSION_LOG")" -eq 2 ]
}

@test "dispatch show with need reports the view pane blocked in the default session" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  [ "$output" = w1:p5 ]
  grep -q '^default | pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | worker | --state | blocked | ' "$FAKE_SESSION_LOG"
}

@test "dispatch show with need names the red view after the project of the worker, also in a worktree" {
  make_repo >/dev/null
  worktree=$(make_worktree)
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_HIDDEN_CWD="$worktree/src"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | repo | --state | blocked | ' "$FAKE_SESSION_LOG"
}

@test "dispatch show with need gives the view pane a seq of digits on macOS" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  as_macos
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  grep -qE '^default \| pane \| report-agent \| w1:p5 \| .* \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
}

@test "dispatch show with no need reports the view of an idle worker as an idle agent, not red, while a reviewr is open" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | worker | --state | idle | ' "$FAKE_SESSION_LOG"
  [ "$(grep -c 'report-agent .* blocked' "$FAKE_LOG")" -eq 0 ]
}

@test "a view of a working worker is an agent that works, so reviewr can send its notes to it" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=working
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | worker | --state | working | ' "$FAKE_SESSION_LOG"
}

@test "a view of a done worker is an idle agent" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=done
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | .* | --state | idle | ' "$FAKE_SESSION_LOG"
}

@test "a view carries the name of its worker, so the reviewr picker shows which worker it is" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_NAME=fix-x FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -qx 'default | agent | rename | w1:p5 | fix-x' "$FAKE_SESSION_LOG"
  # The name comes after the report: Herdr renames only an agent.
  [ "$(grep -n 'report-agent' "$FAKE_SESSION_LOG" | head -n 1 | cut -d: -f1)" -lt \
    "$(grep -n 'agent | rename | w1:p5' "$FAKE_SESSION_LOG" | cut -d: -f1)" ]
}

@test "a view of a worker whose name a user claude already has still opens, with no name" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_NAME=fix-x FAKE_TAB_ROOT=w1:p5 FAKE_NAME_TAKEN=fix-x
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w1:p5 ]
  grep -q '^default | pane | report-agent | w1:p5 | ' "$FAKE_SESSION_LOG"
  # The rename was tried, and Herdr refused it.
  grep -qx 'default | agent | rename | w1:p5 | fix-x' "$FAKE_SESSION_LOG"
}

@test "a view of a worker in a folder named claude is no claude for the name listener" {
  reviewr_beside_view
  mkdir -p "$BATS_TEST_TMPDIR/claude"
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_HIDDEN_CWD="$BATS_TEST_TMPDIR/claude"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | worker | ' "$FAKE_SESSION_LOG"
}

@test "a second show of a view does not report its unchanged state again" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | pane | report-agent | w1:p5 | ' "$FAKE_SESSION_LOG")" -eq 1 ]
}

@test "dispatch show with need reports a reused view pane blocked" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  [ "$output" = w1:p5 ]
  [ "$(grep -c '^default | pane | report-agent | w1:p5 | .* | --state | blocked | ' "$FAKE_SESSION_LOG")" -eq 1 ]
}

@test "dispatch show exits 2 on an unknown mode" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 red
  [ "$status" -eq 2 ]
  [ "$(grep -c '^tab | create' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait turns the red view of a worker that works again into a working agent" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=blocked
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  : >"$FAKE_LOG"
  export FAKE_AGENT_STATUSES="blocked working" FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  [ "$(grep -c '^pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | worker | --state | working | ' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c 'release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait reports the red view as working with the project name of its report" {
  reviewr_beside_view
  make_repo >/dev/null
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=blocked FAKE_HIDDEN_CWD="$BATS_TEST_TMPDIR/repo"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  : >"$FAKE_LOG"
  unset FAKE_HIDDEN_CWD
  export FAKE_AGENT_STATUSES="blocked working" FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  [ "$(grep -c '^pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | repo | --state | working | ' "$FAKE_LOG")" -eq 1 ]
}

@test "dispatch wait reports the red view as working with a seq of digits on macOS" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=blocked
  as_macos
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  : >"$FAKE_LOG"
  export FAKE_AGENT_STATUSES="blocked working" FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  grep -qE '^pane \| report-agent \| w1:p5 \| .* \| --state \| working \| --seq \| [0-9]+$' "$FAKE_LOG"
}

@test "dispatch wait keeps the red view while the worker waits with the same completion seq" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=done FAKE_COMPLETION_SEQS=4
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  : >"$FAKE_LOG"
  export FAKE_AGENT_STATUSES="done idle done" FAKE_SEQS="5 6 7" FAKE_AGENT_GETS=3 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle 4
  [ "$(grep -c 'release-agent\|report-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait turns the red view idle once when the worker ends a new turn" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=done FAKE_COMPLETION_SEQS=4
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  : >"$FAKE_LOG"
  export FAKE_COMPLETION_SEQS="4 8" FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle 4
  [ "$(grep -c '^pane | report-agent | w1:p5 | .* | --state | idle | ' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c 'release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch watch turns the red view into a working agent when the worker works" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=blocked
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  : >"$FAKE_LOG"
  printf 'STATUS: STOP\n' >"$BATS_TEST_TMPDIR/r.md"
  export FAKE_AGENT_STATUSES="blocked working" FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md" blocked
  [ "$(grep -c '^pane | report-agent | w1:p5 | .* | --state | working | ' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c 'release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch show in a pane of the hidden session opens the view in the orchestrator workspace of the board" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w7:p5 HERDR_SESSION=board-workers
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w7","label":"work orchestrator"}]}}'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w1:p9\ttask\twork\t/r.md\n' >"$HOME/.local/state/board-orchestrator/workers-board-workers"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w7:p5 ]
  grep -qx 'default | tab | create | --workspace | w7 | --label | worker | --no-focus' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | workspace | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch show opens the view in the workspace of the orchestrator that calls it" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w5:p5 HERDR_WORKSPACE_ID=w5
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w7","label":"home orchestrator"},{"workspace_id":"w5","label":"home"}]}}'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w1:p9\ttask\thome\t/r.md\n' >"$HOME/.local/state/board-orchestrator/workers-board-workers"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w5:p5 ]
  grep -qx 'default | tab | create | --workspace | w5 | --label | worker | --no-focus' "$FAKE_SESSION_LOG"
}

@test "dispatch show in a pane of the hidden session creates no workspace when the lookup of the user workspaces fails" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w3:p5 FAKE_WORKSPACE_LIST_FAIL=1 HERDR_SESSION=board-workers
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w1:p9\ttask\twork\t/r.md\n' >"$HOME/.local/state/board-orchestrator/workers-board-workers"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 1 ]
  [ "$(grep -c '^default | workspace | create\|^default | tab | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch notify in a pane of the hidden session notifies in the session of the user" {
  export FAKE_AGENT_KIND=claude FAKE_NAME=fix-x HERDR_SESSION=board-workers
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 waits
  [ "$status" -eq 0 ]
  grep -q '^default | notification | show | fix-x needs you' "$FAKE_SESSION_LOG"
}

@test "dispatch show in a pane of the hidden session shows a worker whose prompt failed" {
  export FAKE_FINAL_PROMPT_FAIL=1
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  local pane="${lines[0]}"
  unset FAKE_FINAL_PROMPT_FAIL HERDR_WORKSPACE_ID
  export FAKE_AGENT_KIND=claude HERDR_SESSION=board-workers FAKE_TAB_ROOT=w7:p5
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w7","label":"home orchestrator"}]}}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show "$pane"
  [ "$status" -eq 0 ]
  [ "$output" = w7:p5 ]
  grep -qx 'default | tab | create | --workspace | w7 | --label | worker | --no-focus' "$FAKE_SESSION_LOG"
}

@test "dispatch show exits 1 and opens nothing when the worker is gone" {
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  [ "$(grep -c '^tab | create\|^pane | run' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close closes the worker tab and its view tab" {
  export FAKE_AGENT_KIND=claude FAKE_SESSION=abc-123 FAKE_WS_LABELS='{"w4":"home workers"}' FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  export FAKE_PANE_TAB=w1:t5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = abc-123 ]
  grep -qx 'board-workers | workspace | get | w4' "$FAKE_SESSION_LOG"
  grep -qx 'board-workers | tab | get | w1:t9' "$FAKE_SESSION_LOG"
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^w1:p9' "$HOME/.local/state/board-orchestrator/views-board-workers")" -eq 0 ]
}

@test "a worker view that the user split closes with its whole tab when the worker closes" {
  export FAKE_AGENT_KIND=claude FAKE_SESSION=abc-123 FAKE_WS_LABELS='{"w4":"home workers"}' FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  export FAKE_PANE_TAB=w1:t5 FAKE_VIEW_TAB_PANES=2
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = abc-123 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | pane | close' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch close refuses when the user looks at the view of the worker" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}' FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  export FAKE_PANE_FOCUSED=true
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  grep -qx 'default | pane | get | w1:p5' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close with no view closes only the worker tab" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | tab | close' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch wait reads the worker in the hidden session and notifies in the default session" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_NAME=fix-x FAKE_AGENT_GETS=6 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  grep -qx 'board-workers | agent | get | w1:p9' "$FAKE_SESSION_LOG"
  grep -q '^default | notification | show | fix-x needs you' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | agent' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch watch reads the worker in the hidden session" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_GETS=1 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
  grep -qx 'board-workers | agent | get | w1:p9' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | agent' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch notify reads the name in the hidden session and notifies in the default session" {
  export FAKE_AGENT_KIND=claude FAKE_NAME=fix-x
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" notify w1:p9 waits
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | agent | get | w1:p9' "$FAKE_SESSION_LOG"
  grep -qx 'default | notification | show | fix-x needs you | --body | The worker waits for the user. | --sound | request' "$FAKE_SESSION_LOG"
}

# Point the view w1:p5 of the worker w1:p9 at another worker, as a reused pane ID does.
stale_view() {
  printf '%s --session board-workers agent attach w1:p3' "$HERDR_BIN_PATH" >"$FAKE_LOG.run.w1:p5"
}

@test "dispatch show does not reuse a view that attaches to another worker" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  stale_view
  export FAKE_TAB_ROOT=w1:p6
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = w1:p6 ]
  grep -q '^default | pane | process-info | --pane | w1:p5' "$FAKE_SESSION_LOG"
}

@test "dispatch show exits 1 and keeps no view when the attach does not run" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_ATTACH_DEAD=1 DISPATCH_ATTACH_WAIT=1
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  [ ! -f "$HOME/.local/state/board-orchestrator/views-board-workers" ] ||
    [ "$(grep -c '^w1:p9' "$HOME/.local/state/board-orchestrator/views-board-workers")" -eq 0 ]
}

@test "dispatch close does not close a view that attaches to another worker" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}' FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  stale_view
  export FAKE_PANE_TAB=w1:t5 FAKE_PANE_FOCUSED=true
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^default | tab | close' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch close wait waits until the view loses the focus and the worker is done" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}' FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  : >"$FAKE_LOG"
  : >"$FAKE_SESSION_LOG"
  export FAKE_PANE_TAB=w1:t5 FAKE_PANE_FOCUSED_CALLS=3 FAKE_AGENT_STATUSES="working working working working done" DISPATCH_POLL=0 DISPATCH_CLOSE_WAIT=0
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" close w1:p9 wait
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | pane | get | w1:p5' "$FAKE_SESSION_LOG")" -ge 4 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
}

@test "dispatch close closes the tab of a pane whose agent is gone, and its view" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}' FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  unset FAKE_AGENT_KIND
  export FAKE_PANE_TAB=w1:t5 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  grep -qx 'board-workers | pane | get | w1:p9' "$FAKE_SESSION_LOG"
  grep -qx 'board-workers | workspace | get | w4' "$FAKE_SESSION_LOG"
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
  grep -qx 'default | tab | close | w1:t5' "$FAKE_SESSION_LOG"
}

@test "dispatch close of a gone agent refuses a pane outside a workers workspace" {
  export FAKE_WS_LABELS='{"w4":"home orchestrator"}' DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tab | close' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch close counts the agent gone only after 3 misses in a row" {
  export FAKE_WS_LABELS='{"w4":"home workers"}' DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
  grep -qx 'board-workers | tab | close | w1:t9' "$FAKE_SESSION_LOG"
}

# Write the screen file $1 with a Claude Code idle prompt and the bottom bar $2.
screen() {
  printf '● Started make quality in the background.\n\n✻ Churned for 32s · done 12:18 PM%s\n\n────\n❯ \n────\n  %s\n' "${3:-}" "$2" >"$BATS_TEST_TMPDIR/$1"
}

@test "dispatch wait exits 3 idle-job with no notification while the bottom bar shows 1 shell" {
  screen s1 '⏵⏵ auto mode on · 1 shell · ← 1 agent · ↓ to manage'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 FAKE_COMPLETION_SEQS=5 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle-job 5" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 2 ]
  grep -q '^board-workers | pane | read | w1:p9 | --source | visible' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^notification | show' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait exits 3 idle-job while the bottom bar shows 2 shells" {
  screen s1 '⏵⏵ auto mode on · 2 shells · ← 1 agent · ↓ to manage'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = idle-job ]
}

@test "dispatch wait exits 3 idle-job while the done line shows a shell still running" {
  screen s1 '⏵⏵ auto mode on · ← 1 agent' ' · 1 shell still running'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = idle-job ]
}

@test "dispatch wait exits 3 idle-job while a background subagent runs with no shell" {
  printf '✻ Churned for 31s · done 4:56 PM\n────\n❯ \n────\n  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent · ↓ to manage\n  ● main\n  ◯ general-purpose  Run the checks                 1m 57s · ↓ 7.3k tokens\n' >"$BATS_TEST_TMPDIR/s1"
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 FAKE_COMPLETION_SEQS=4 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle-job 4" ]
  [ "$(grep -c '^notification | show' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait exits 3 idle with a notification after two checks with only an agent count on the bar" {
  screen s1 '⏵⏵ auto mode on · ← 1 agent'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=4 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = idle ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 2 ]
  grep -q '^notification | show' "$FAKE_LOG"
}

@test "dispatch wait with SEEN idle-job waits while the job runs, then exits 3 idle with a notification" {
  screen s1 '⏵⏵ auto mode on · 1 shell · ↓ to manage'
  screen s2 '⏵⏵ auto mode on · ← 1 agent'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 FAKE_COMPLETION_SEQS=5 DISPATCH_POLL=0
  export FAKE_SCREENS="$BATS_TEST_TMPDIR/s1 $BATS_TEST_TMPDIR/s1 $BATS_TEST_TMPDIR/s1 $BATS_TEST_TMPDIR/s2"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle-job 5
  [ "$status" -eq 3 ]
  [ "$output" = "idle 5" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 5 ]
  grep -q '^notification | show' "$FAKE_LOG"
}

@test "dispatch wait with SEEN idle-job does not exit 3 while the job runs" {
  screen s1 '⏵⏵ auto mode on · 1 shell · ↓ to manage'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=5 FAKE_AGENT_GETS=4 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle-job 5
  [ "$status" -eq 1 ]
}

@test "dispatch wait with SEEN idle-job exits 3 idle-job on a new completion seq" {
  screen s1 '⏵⏵ auto mode on · 1 shell · ↓ to manage'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 FAKE_COMPLETION_SEQS="5 5 6" DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" idle-job 5
  [ "$status" -eq 3 ]
  [ "$output" = "idle-job 6" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 4 ]
  [ "$(grep -c '^notification | show' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch wait exits 0 on a report before idle-job" {
  screen s1 '⏵⏵ auto mode on · 1 shell · ↓ to manage'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_AGENT_GETS=8 FAKE_REPORT_AT="2 $BATS_TEST_TMPDIR/r.md" DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Write a transcript for the session $1 under $CLAUDE_CONFIG_DIR/projects/p.
transcript() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
  cat >"$CLAUDE_CONFIG_DIR/projects/p/$1.jsonl"
}

@test "dispatch last prints the text of the last assistant line that has text" {
  transcript s-1 <<'EOF2'
{"type":"user","message":{"content":[{"type":"text","text":"Do the task."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"First answer."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Part one."},{"type":"tool_use","name":"Bash"},{"type":"text","text":"Part two."}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}
EOF2
  export FAKE_AGENT_KIND=claude FAKE_SESSION=s-1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" last w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = "Part one.
Part two." ]
  grep -q '^board-workers | agent | get | w1:p9' "$FAKE_SESSION_LOG"
}

@test "dispatch last prints the text of the last assistant line on macOS" {
  transcript s-1 <<'EOF2'
{"type":"assistant","message":{"content":[{"type":"text","text":"First answer."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Last answer."}]}}
EOF2
  export FAKE_AGENT_KIND=claude FAKE_SESSION=s-1
  as_macos
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" last w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = "Last answer." ]
  [ -z "$stderr" ]
}

@test "dispatch last cuts a long text to the last 3000 characters" {
  long=$(printf 'a%.0s' {1..2000})$(printf 'b%.0s' {1..3000})
  jq -cn --arg t "$long" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}' >"$BATS_TEST_TMPDIR/line"
  transcript s-1 <"$BATS_TEST_TMPDIR/line"
  export FAKE_AGENT_KIND=claude FAKE_SESSION=s-1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" last w1:p9
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 3000 ]
  [ "$(grep -c a <<<"$output")" -eq 0 ]
}

@test "dispatch last prints the screen when there is no transcript" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  printf 'line one\nline two\n' >"$BATS_TEST_TMPDIR/s1"
  export FAKE_AGENT_KIND=claude FAKE_SESSION=s-9 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" last w1:p9
  [ "$status" -eq 0 ]
  [ "$output" = "line one
line two" ]
  grep -q '^board-workers | pane | read | w1:p9 | --source | visible' "$FAKE_SESSION_LOG"
}

@test "dispatch last exits 1 when the agent is gone" {
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" last w1:p9
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
}

@test "dispatch watch exits 3 idle with no notification on a new completion seq and an unchanged report" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS="3 4" FAKE_AGENT_GETS=8 DISPATCH_POLL=0
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle 4" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch watch does not exit 3 while idle with the completion seq of the start" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4 FAKE_AGENT_GETS=4 DISPATCH_POLL=0
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
}

@test "dispatch watch with idle SEQ and the same seq does not exit 3" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working idle" FAKE_COMPLETION_SEQS="3 4" FAKE_AGENT_GETS=5 DISPATCH_POLL=0
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md" idle 4
  [ "$status" -eq 1 ]
}

@test "dispatch watch exits 3 idle-job on a job screen" {
  screen s1 '⏵⏵ auto mode on · 1 shell · ↓ to manage'
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS="3 4" FAKE_AGENT_GETS=8 DISPATCH_POLL=0 FAKE_SCREENS="$BATS_TEST_TMPDIR/s1"
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle-job 4" ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch watch exits 3 blocked with a notification" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_SEQS=5 FAKE_NAME=fix-x FAKE_AGENT_GETS=8 DISPATCH_POLL=0
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 3 ]
  [ "$output" = "blocked 5" ]
  [ "$(grep -c '^notification | show | fix-x needs you' "$FAKE_LOG")" -eq 1 ]
}

@test "dispatch watch with blocked SEQ does not exit 3 again for the same prompt" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=blocked FAKE_SEQS=5 FAKE_AGENT_GETS=3 DISPATCH_POLL=0
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md" blocked 5
  [ "$status" -eq 1 ]
  [ "$(grep -c '^notification' "$FAKE_LOG")" -eq 0 ]
}

@test "a watch reports a worker at a permission prompt at once after its status event, not after the poll interval" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working blocked" FAKE_SEQS="4 5" DISPATCH_POLL=60
  status_event "$BATS_TEST_TMPDIR/ev" w1:p9 blocked
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr timeout 10 bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 3 ]
  [ "$output" = "blocked 5" ]
  grep -q '"pane_id":"w1:p9"' "$FAKE_LOG.nc"
}

@test "a wait reports an idle worker after the settle time, not after the poll interval" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working idle" FAKE_COMPLETION_SEQS="3 4" DISPATCH_POLL=60 DISPATCH_SETTLE=1
  status_event "$BATS_TEST_TMPDIR/ev" w1:p9 idle
  run --separate-stderr timeout 10 bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle 4" ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
}

@test "a watch does not wake for an event of another pane" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working blocked" FAKE_SEQS="4 5" DISPATCH_POLL=60
  status_event "$BATS_TEST_TMPDIR/ev" w1:p8 blocked
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr timeout 3 bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 124 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 1 ]
}

@test "a wait sees a report file at the poll interval when no event comes" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working DISPATCH_POLL=2
  : >"$BATS_TEST_TMPDIR/ev"
  : >"$BATS_TEST_TMPDIR/ev.more"
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev $BATS_TEST_TMPDIR/ev.more"
  (sleep 1; printf 'STATUS: OK\n' >"$BATS_TEST_TMPDIR/r.md") &
  run --separate-stderr timeout 10 bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ -s "$FAKE_LOG.nc" ]
}

@test "a wait falls back to sleep when the socket is missing" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4 DISPATCH_POLL=1
  printf 'board-workers\n' >"$FAKE_LOG.stopped"
  run --separate-stderr timeout 10 bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle 4" ]
  [ ! -e "$FAKE_LOG.nc" ]
}

@test "a wait falls back to sleep when nc cannot connect" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4 DISPATCH_POLL=1
  run --separate-stderr timeout 10 bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ "$output" = "idle 4" ]
  [ -s "$FAKE_LOG.nc" ]
  [ -z "$(event_dirs)" ]
}

@test "a wait leaves no nc process and no fifo behind" {
  cp "$BATS_TEST_DIRNAME/fake-nc" "$BATS_TEST_TMPDIR/nc"
  export DISPATCH_NC="$BATS_TEST_TMPDIR/nc" FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working blocked" FAKE_SEQS="4 5" DISPATCH_POLL=60
  status_event "$BATS_TEST_TMPDIR/ev" w1:p9 blocked
  run --separate-stderr timeout 10 bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 3 ]
  [ -s "$FAKE_LOG.nc" ]
  sleep 0.5
  [ -z "$(pgrep -f "$BATS_TEST_TMPDIR/nc")" ]
  [ -z "$(event_dirs)" ]
}

@test "a watch stopped by a signal leaves no nc process and no fifo behind" {
  cp "$BATS_TEST_DIRNAME/fake-nc" "$BATS_TEST_TMPDIR/nc"
  export DISPATCH_NC="$BATS_TEST_TMPDIR/nc" FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working DISPATCH_POLL=60
  status_event "$BATS_TEST_TMPDIR/ev" w1:p9 working
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md" >/dev/null 2>&1 3>&- &
  pid=$!
  sleep 2
  pgrep -f "$BATS_TEST_TMPDIR/nc"
  kill -TERM "$pid"
  wait "$pid" || true
  sleep 0.5
  [ -z "$(pgrep -f "$BATS_TEST_TMPDIR/nc")" ]
  [ -z "$(event_dirs)" ]
}

@test "dispatch watch: a report change wins over a new turn end" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS="3 4" FAKE_AGENT_GETS=8 DISPATCH_POLL=0
  export FAKE_REPORT_AT="3 $BATS_TEST_TMPDIR/r.md"
  printf 'RESULT: WAITS FOR USER\n' >"$BATS_TEST_TMPDIR/r.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" watch w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dispatch remind prompts an idle worker in the hidden session with the report path" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" remind w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 1 ]
  grep -q "^board-workers | agent | prompt | w1:p9 | Write the report again to $BATS_TEST_TMPDIR/r.md now" "$FAKE_SESSION_LOG"
  [ "$(grep -c 'focus' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch remind waits while the user focuses the view, then prompts" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  : >"$FAKE_LOG"
  : >"$FAKE_SESSION_LOG"
  export FAKE_PANE_TAB=w1:t5 FAKE_PANE_FOCUSED_CALLS=2 DISPATCH_POLL=0
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" remind w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | pane | get | w1:p5' "$FAKE_SESSION_LOG")" -eq 3 ]
  local third prompt
  third=$(grep -n '^default | pane | get | w1:p5' "$FAKE_SESSION_LOG" | sed -n 3p | cut -d: -f1)
  prompt=$(grep -n '^board-workers | agent | prompt | w1:p9' "$FAKE_SESSION_LOG" | cut -d: -f1)
  [ "$(grep -c '^board-workers | agent | prompt' "$FAKE_SESSION_LOG")" -eq 1 ]
  [ "$prompt" -gt "$third" ]
  [ "$(grep -c 'focus' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch remind exits 1 with no prompt while the worker is working" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" remind w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the worker is working"* ]]
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch remind exits 1 when the prompt fails" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_FINAL_PROMPT_FAIL=1 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" remind w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"could not prompt"* ]]
}

@test "dispatch remind exits 1 when the agent is gone" {
  export DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" remind w1:p9 "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch answer prompts an idle worker in the hidden session with the words of the user" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle DISPATCH_POLL=0
  printf 'Take the second choice.\nKeep the old name.\n' >"$BATS_TEST_TMPDIR/a.txt"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^board-workers | agent | prompt' "$FAKE_SESSION_LOG")" -eq 1 ]
  grep -q '^board-workers | agent | prompt | w1:p9 | The user answers through the orchestrator:$' "$FAKE_SESSION_LOG"
  grep -q '^Take the second choice\.$' "$FAKE_SESSION_LOG"
  grep -q '^Keep the old name\.$' "$FAKE_SESSION_LOG"
  [ "$(grep -c 'focus' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch answer waits while the user focuses the view, then prompts" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_TAB_ROOT=w1:p5
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  : >"$FAKE_LOG"
  : >"$FAKE_SESSION_LOG"
  printf 'Yes.\n' >"$BATS_TEST_TMPDIR/a.txt"
  export FAKE_PANE_TAB=w1:t5 FAKE_PANE_FOCUSED_CALLS=2 DISPATCH_POLL=0
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^default | pane | get | w1:p5' "$FAKE_SESSION_LOG")" -eq 3 ]
  local third prompt
  third=$(grep -n '^default | pane | get | w1:p5' "$FAKE_SESSION_LOG" | sed -n 3p | cut -d: -f1)
  prompt=$(grep -n '^board-workers | agent | prompt | w1:p9' "$FAKE_SESSION_LOG" | cut -d: -f1)
  [ "$(grep -c '^board-workers | agent | prompt' "$FAKE_SESSION_LOG")" -eq 1 ]
  [ "$prompt" -gt "$third" ]
  [ "$(grep -c 'focus' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch answer waits while the worker is working, then prompts" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="working working idle" DISPATCH_POLL=0
  printf 'Yes.\n' >"$BATS_TEST_TMPDIR/a.txt"
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
  local third prompt
  third=$(grep -n '^agent | get' "$FAKE_LOG" | sed -n 3p | cut -d: -f1)
  prompt=$(grep -n '^agent | prompt' "$FAKE_LOG" | cut -d: -f1)
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 1 ]
  [ "$prompt" -gt "$third" ]
}

@test "dispatch answer waits while the worker is blocked, then prompts" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="blocked blocked done" DISPATCH_POLL=0
  printf 'Yes.\n' >"$BATS_TEST_TMPDIR/a.txt"
  run --separate-stderr timeout 20 bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent | get' "$FAKE_LOG")" -eq 3 ]
  local third prompt
  third=$(grep -n '^agent | get' "$FAKE_LOG" | sed -n 3p | cut -d: -f1)
  prompt=$(grep -n '^agent | prompt' "$FAKE_LOG" | cut -d: -f1)
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 1 ]
  [ "$prompt" -gt "$third" ]
}

@test "dispatch answer exits 1 when the agent is gone" {
  export DISPATCH_POLL=0
  printf 'Yes.\n' >"$BATS_TEST_TMPDIR/a.txt"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "dispatch answer exits 2 with no Herdr call when the file is missing or empty" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/none.txt"
  [ "$status" -eq 2 ]
  : >"$BATS_TEST_TMPDIR/empty.txt"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/empty.txt"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"missing or empty"* ]]
  [ "$(wc -l <"$FAKE_LOG")" -eq 0 ]
}

@test "dispatch answer exits 1 when the prompt fails" {
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_FINAL_PROMPT_FAIL=1 DISPATCH_POLL=0
  printf 'Yes.\n' >"$BATS_TEST_TMPDIR/a.txt"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" answer w1:p9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"could not prompt"* ]]
}

# The state file of the workers of the hidden session board-workers.
workers_file() {
  printf '%s\n' "$HOME/.local/state/board-orchestrator/workers-board-workers"
}

@test "dispatch start records the worker, and a new start on the same pane replaces the line" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w1","label":"home orchestrator"},{"workspace_id":"w3","label":"home workers"}]}}'
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  local first="${lines[1]}"
  [ "$(cat "$(workers_file)")" = "w1:p9	task	home	$first" ]
  readonly_list "$BATS_TEST_TMPDIR" '["Bash(ls)"]'
  run bash "$PLUGIN_DIR/dispatch.sh" start auto "$BATS_TEST_TMPDIR" "Check Y" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" != "$first" ]
  [ "$(cat "$(workers_file)")" = "w1:p9	auto	home	${lines[1]}" ]
}

@test "dispatch close removes the line of its pane from the workers file" {
  export FAKE_AGENT_KIND=claude FAKE_WS_LABELS='{"w4":"home workers"}'
  mkdir -p "$(dirname "$(workers_file)")"
  printf 'w1:p9\ttask\thome\t/r/a.md\nw1:p8\tauto\thome\t/r/b.md\n' >"$(workers_file)"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" close w1:p9
  [ "$status" -eq 0 ]
  [ "$(cat "$(workers_file)")" = "w1:p8	auto	home	/r/b.md" ]
}

# The workspace w1 "home orchestrator" of the user with the label $1 (default: no count),
# and the hidden workspace w3 "home workers" with $2 claude workers in the status $3
# (working by default).
orchestrator_with_workers() {
  local i agents='[]'
  export FAKE_WORKSPACES_JSON
  FAKE_WORKSPACES_JSON=$(jq -cn --arg l "${1:-home orchestrator}" '{result: {workspaces: [{workspace_id: "w1", label: $l}]}}')
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  for ((i = 1; i <= $2; i++)); do
    agents=$(jq -c --arg p "w3:p$i" --arg st "${3:-working}" '. + [{pane_id: $p, agent: "claude", agent_status: $st, workspace_id: "w3"}]' <<<"$agents")
  done
  export FAKE_HIDDEN_AGENTS_JSON
  FAKE_HIDDEN_AGENTS_JSON=$(jq -cn --argjson a "$agents" '{result: {agents: $a}}')
}

@test "dispatch workers shows the number of workers on the second line of the orchestrator workspace" {
  orchestrator_with_workers "" 2
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=2 workers \| (--token \| working=[^|]+|--clear-token \| working) \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
}

@test "dispatch workers says 1 worker for a board with one worker" {
  orchestrator_with_workers "" 1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| (--token \| working=[^|]+|--clear-token \| working) \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
}

@test "dispatch workers shows 0 workers when the last worker is gone" {
  orchestrator_with_workers "" 0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=0 workers \| (--token \| working=[^|]+|--clear-token \| working) \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
}

@test "dispatch workers gives back the plain name to an orchestrator workspace with the count in its name" {
  orchestrator_with_workers "home orchestrator · 2 workers" 2
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qx 'default | workspace | rename | w1 | home orchestrator' "$FAKE_SESSION_LOG"
}

@test "dispatch workers does not rename an orchestrator workspace with the plain name" {
  orchestrator_with_workers "" 2
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(grep -c 'workspace | rename' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch workers shows the number of working workers on the orchestrator workspace, with no agent" {
  orchestrator_with_workers "" 2 working
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=2 workers \| --token \| working=2 working \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
  [ "$(grep -c 'report-agent' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "dispatch workers clears the working count of the orchestrator workspace when no worker works" {
  orchestrator_with_workers "" 2 done
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=2 workers \| --clear-token \| working \| --seq \| [0-9]+$' "$FAKE_SESSION_LOG"
}

@test "dispatch wait updates the orchestrator workspace when the status of the worker changes" {
  orchestrator_with_workers "" 1 working
  mkdir -p "$(dirname "$(workers_file)")"
  printf 'w1:p9\ttask\thome\t%s\n' "$BATS_TEST_TMPDIR/none.md" >"$(workers_file)"
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUSES="blocked working" FAKE_AGENT_GETS=2 DISPATCH_POLL=0
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" wait w1:p9 "$BATS_TEST_TMPDIR/none.md" blocked
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| ' "$FAKE_SESSION_LOG"
}

@test "the orchestrator workspace of the user with a count is still the workspace of the board" {
  orchestrator_with_workers "home orchestrator · 2 workers" 2
  run bash -c 'source "$1/lib.sh"; board_workspace_id home' _ "$PLUGIN_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = w1 ]
}

@test "dispatch workers lists the agents of the workers workspace of the board" {
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"},{"workspace_id":"w5","label":"lab workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"fix-x","agent_status":"done","completion_seq":12,"state_change_seq":14,"workspace_id":"w3"},{"pane_id":"w5:p1","name":"lab-z","agent_status":"idle","workspace_id":"w5"},{"pane_id":"w3:p2","name":"other-y","agent_status":"working","state_change_seq":7,"workspace_id":"w3"}]}}'
  printf 'RESULT: DONE\nmore\n' >"$dir/fix-x-20260101-100000-1-1.md"
  printf 'w3:p1\ttask\thome\t%s\n' "$dir/fix-x-20260101-100000-1-1.md" >"$(workers_file)"
  printf 'old\n' >"$dir/other-y-20260101-100000-1-1.md"
  touch -d '2026-01-01 10:00:00' "$dir/other-y-20260101-100000-1-1.md"
  printf 'new\n' >"$dir/other-y-20260102-100000-1-1.md"
  touch -d '2026-01-02 10:00:00' "$dir/other-y-20260102-100000-1-1.md"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(jq -r '[.pane, .name, .status, .seq, .mode, .report_exists, .first_line, .view] | map(tostring) | join(" ")' <<<"${lines[0]}")" = "w3:p1 fix-x done 12 task true RESULT: DONE null" ]
  [ "$(jq -r .report <<<"${lines[0]}")" = "$dir/fix-x-20260101-100000-1-1.md" ]
  [ "$(jq -r '.report_mtime | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' <<<"${lines[0]}")" = true ]
  [ "$(jq -r '[.pane, .name, .status, .seq, .mode, .report_exists, .first_line] | map(tostring) | join(" ")' <<<"${lines[1]}")" = "w3:p2 other-y working 7 null true new" ]
  [ "$(jq -r .report <<<"${lines[1]}")" = "$dir/other-y-20260102-100000-1-1.md" ]
}

@test "dispatch workers gives the report mtime in ISO 8601 on macOS" {
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  export TZ=UTC
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"fix-x","agent_status":"done","completion_seq":12,"workspace_id":"w3"}]}}'
  printf 'RESULT: DONE\n' >"$dir/fix-x-20260101-100000-1-1.md"
  touch -d '2026-01-01 10:00:00' "$dir/fix-x-20260101-100000-1-1.md"
  printf 'w3:p1\ttask\thome\t%s\n' "$dir/fix-x-20260101-100000-1-1.md" >"$(workers_file)"
  as_macos
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(jq -r .report_mtime <<<"${lines[0]}")" = 2026-01-01T10:00:00+00:00 ]
}

@test "dispatch workers gives waits false for a live worker with an old WAITS FOR USER report" {
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"a","agent_status":"done","workspace_id":"w3"},{"pane_id":"w3:p2","name":"b","agent_status":"working","workspace_id":"w3"},{"pane_id":"w3:p3","name":"c","agent_status":"done","workspace_id":"w3"},{"pane_id":"w3:p4","name":"d","agent_status":"blocked","workspace_id":"w3"},{"pane_id":"w3:p5","name":"e","agent_status":"idle","workspace_id":"w3"}]}}'
  : >"$(workers_file)"
  for p in 1 2 3 4; do
    printf 'RESULT: WAITS FOR USER\n' >"$dir/r$p.md"
    printf 'w3:p%s\ttask\thome\t%s\n' "$p" "$dir/r$p.md" >>"$(workers_file)"
  done
  printf 'RESULT: DONE\n' >"$dir/r5.md"
  printf 'w3:p5\ttask\thome\t%s\n' "$dir/r5.md" >>"$(workers_file)"
  # The screen reads of the idle and done workers p1, p3 and p5: a job, then no job.
  screen s1 '⏵⏵ auto mode on · 1 shell · ↓ to manage'
  screen s2 '⏵⏵ auto mode on'
  export FAKE_SCREENS="$BATS_TEST_TMPDIR/s1 $BATS_TEST_TMPDIR/s2"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(jq -sr 'map([.pane, .job, .live, .waits] | map(tostring) | join(" ")) | join(",")' <<<"$output")" = \
    "w3:p1 true true false,w3:p2 false true false,w3:p3 false false true,w3:p4 false false true,w3:p5 false false false" ]
}

@test "dispatch workers gives null fields when no report matches" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"fix-x","agent_status":"idle","workspace_id":"w3"}]}}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.seq, .mode, .report, .report_exists, .first_line, .report_mtime, .view]' <<<"$output")" = '[null,null,null,false,null,null,null]' ]
}

@test "dispatch workers takes the report path from the worker prompt when no report exists" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"fix-x","agent_status":"working","workspace_id":"w3"}]}}'
  export FAKE_SESSION=s-9 FAKE_AGENT_KIND=claude
  local r="$BATS_TEST_TMPDIR/fix-x-20261023-101010-1-2.md"
  transcript s-9 <<EOF2
{"type":"user","message":{"content":[{"type":"text","text":"Do the task.\\n\\nWhen you finish, write your report to $r. Do not merge."}]}}
{"type":"user","message":{"content":[{"type":"text","text":"write your report to /other/path.md"}]}}
EOF2
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(jq -r .report <<<"$output")" = "$r" ]
  [ "$(jq -r .report_exists <<<"$output")" = false ]
}

@test "dispatch workers prints nothing and exits 0 when the workspace does not exist" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w5","label":"lab workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w5:p1","name":"lab-z","agent_status":"idle","workspace_id":"w5"}]}}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dispatch workers exits 1 when the hidden session does not run" {
  export FAKE_SESSION_RUNNING=""
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ -n "$stderr" ]
}

@test "dispatch workers gives the view of a worker when the view is valid" {
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"fix-x","agent_status":"idle","workspace_id":"w3"}]}}'
  printf 'w3:p1 w1:p5\n' >"$dir/views-board-workers"
  printf '%s --session board-workers agent attach w3:p1' "$HERDR_BIN_PATH" >"$FAKE_LOG.run.w1:p5"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(jq -r .view <<<"$output")" = w1:p5 ]
}

@test "dispatch workers finds the report of a name with a number added" {
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  printf 'RESULT: DONE\n' >"$dir/fix-x-20260101-100000-1-1.md"
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"home workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"pane_id":"w3:p1","name":"fix-x-2","agent_status":"idle","workspace_id":"w3"}]}}'
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(jq -r .report <<<"$output")" = "$dir/fix-x-20260101-100000-1-1.md" ]
}

@test "a worker that starts to work shows at once as 1 working on the orchestrator workspace" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"},{"pane_id":"w7:p1","workspace_id":"w7","agent":"claude","agent_status":"idle"}]'
  jq -cn '{result: {agents: [{pane_id: "w9:p1", workspace_id: "w9", agent: "claude", agent_status: "working"},
    {pane_id: "w7:p1", workspace_id: "w7", agent: "claude", agent_status: "idle"}]}}' >"$BATS_TEST_TMPDIR/later.json"
  export FAKE_NC_AGENTS_LATE="$BATS_TEST_TMPDIR/later.json" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  printf '%s\n' '{"data":{"agent":"claude","agent_status":"working","pane_id":"w9:p1","workspace_id":"w9"},"event":"pane.agent_status_changed"}' >"$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '"type":"pane.agent_status_changed","pane_id":"w9:p1"' "$FAKE_LOG.nc"
  # w7 is no workers workspace.
  [ "$(grep -c '"pane_id":"w7:p1"' "$FAKE_LOG.nc")" -eq 0 ]
  # One count at the start, one for the event.
  [ "$(grep -c 'workspace | report-metadata' "$FAKE_SESSION_LOG")" -eq 2 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| --token \| working=1 working \| --seq' "$FAKE_SESSION_LOG"
}

@test "a count listener restarts with the new code after a change to lib.sh" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  # A copy of the plugin: the test changes its lib.sh.
  cp -R "$PLUGIN_DIR" "$BATS_TEST_TMPDIR/plugin"
  # Before the first reply, a new show_worker_count goes into lib.sh, as a git pull does.
  cat >"$BATS_TEST_TMPDIR/nc" <<EOF
#!/usr/bin/env bash
if [ ! -e "$BATS_TEST_TMPDIR/changed" ]; then
  : >"$BATS_TEST_TMPDIR/changed"
  printf 'show_worker_count() { echo "\$1" >>"$BATS_TEST_TMPDIR/new-code"; }\n' >>"$BATS_TEST_TMPDIR/plugin/lib.sh"
fi
exec "$BATS_TEST_DIRNAME/fake-nc" "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/nc"
  export DISPATCH_NC="$BATS_TEST_TMPDIR/nc" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1 $BATS_TEST_TMPDIR/ev2"
  printf '%s\n' '{"data":{"agent":"claude","agent_status":"working","pane_id":"w9:p1","workspace_id":"w9"},"event":"pane.agent_status_changed"}' >"$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev2"
  run timeout 10 bash "$BATS_TEST_TMPDIR/plugin/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_LOG.nc")" -eq 2 ]
  grep -qx home "$BATS_TEST_TMPDIR/new-code"
}

@test "a new worker pane makes the listener subscribe again, now with that pane" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  jq -cn '{result: {agents: [{pane_id: "w9:p1", workspace_id: "w9", agent: "claude", agent_status: "idle"},
    {pane_id: "w9:p2", workspace_id: "w9", agent: "claude", agent_status: "idle"}]}}' >"$BATS_TEST_TMPDIR/later.json"
  export FAKE_NC_AGENTS_LATE="$BATS_TEST_TMPDIR/later.json" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1 $BATS_TEST_TMPDIR/ev2"
  printf '%s\n' '{"data":{"pane_id":"w9:p2","workspace_id":"w9"},"event":"pane.created"}' >"$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev2"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
    [ "$(wc -l <"$FAKE_LOG.nc")" -eq 2 ]
  [ "$(head -1 "$FAKE_LOG.nc" | grep -c '"pane_id":"w9:p2"')" -eq 0 ]
  tail -1 "$FAKE_LOG.nc" | grep -q '"type":"pane.agent_status_changed","pane_id":"w9:p2"'
  tail -1 "$FAKE_LOG.nc" | grep -q '"type":"pane.created"'
}

@test "a second listener exits at once when one already runs" {
  count_watch_board '[]'
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  exec 8>>"$dir/count-watch-board-workers.lock"
  flock 8
  run timeout 5 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  exec 8>&-
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_LOG.nc" ]
}

@test "opening a board starts the listener of the worker counts" {
  export FAKE_CWD="/work/project" FAKE_DEFAULT_WS_ROOT=w3:p1
  OBSIDIAN_VAULT_PATH=/vault run timeout 20 bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  local i
  for i in $(seq 50); do [ ! -s "$FAKE_LOG.nc" ] || break; sleep 0.1; done
  grep -q '"method":"events.subscribe"' "$FAKE_LOG.nc"
}

@test "dispatch start starts the listener of the worker counts" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  local i
  for i in $(seq 50); do [ ! -s "$FAKE_LOG.nc" ] || break; sleep 0.1; done
  grep -q '"method":"events.subscribe"' "$FAKE_LOG.nc"
}

@test "a worker that comes while the listener subscribes gets a status subscription" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  jq -cn '{result: {agents: [{pane_id: "w9:p1", workspace_id: "w9", agent: "claude", agent_status: "idle"},
    {pane_id: "w9:p2", workspace_id: "w9", agent: "claude", agent_status: "idle"}]}}' >"$BATS_TEST_TMPDIR/later.json"
  export FAKE_NC_AGENTS="$BATS_TEST_TMPDIR/later.json" FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1 $BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
    [ "$(wc -l <"$FAKE_LOG.nc")" -eq 2 ]
  tail -1 "$FAKE_LOG.nc" | grep -q '"type":"pane.agent_status_changed","pane_id":"w9:p2"'
}

@test "an error reply of the server makes the listener subscribe again" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1 $BATS_TEST_TMPDIR/ev2"
  printf '%s\n' '{"id":"count-watch","error":{"code":"internal_error"}}' >"$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev2"
  run timeout 10 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
    [ "$(wc -l <"$FAKE_LOG.nc")" -eq 2 ]
}

@test "the listener waits out a hidden session that does not answer for a moment" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  export FAKE_HIDDEN_LIST_FAILS=1 FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '"method":"events.subscribe"' "$FAKE_LOG.nc"
}

@test "the listener exits 1 and does not die of SIGPIPE when nc cannot connect" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  export FAKE_NC_REFUSE=1
  run timeout 10 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ -e "$FAKE_LOG.nc-refused" ]
  [ "$status" -eq 1 ]
}

@test "showing a running orchestrator starts the listener of the worker counts" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[]}}' FAKE_HIDDEN_AGENTS_JSON='{"result":{"agents":[]}}'
  OBSIDIAN_VAULT_PATH= run timeout 20 bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  local i
  for i in $(seq 50); do [ ! -s "$FAKE_LOG.nc" ] || break; sleep 0.1; done
  grep -q '"method":"events.subscribe"' "$FAKE_LOG.nc"
}

@test "the orchestrator shows 0 workers after its last worker ends outside dispatch close" {
  count_watch_board '[]'
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[]}}'
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=0 workers \| --clear-token \| working' "$FAKE_SESSION_LOG"
}

# Write the attach of the hidden pane $2 as the command of the view pane $1.
view_runs() {
  printf '%s' "$HERDR_BIN_PATH --session board-workers agent attach $2" >"$FAKE_LOG.run.$1"
}

# The orchestrator of the board work runs in w3:p1, in the workspace "work orchestrator"
# (w3) of the user. The view w3:p2 there shows the worker w4:p2 of the hidden workspace
# "work workers" (w4).
one_orchestrator() {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w3:p1"},{"pane_id":"w3:p2"}]}}'
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w4","label":"work workers"}]}}'
  export FAKE_HIDDEN_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","pane_id":"w4:p2","workspace_id":"w4"}]}}'
  export FAKE_AGENT_KIND=claude
  view_runs w3:p2 w4:p2
}

# The orchestrators of the boards work (w3:p1 in w3) and home (w6:p1 in w6, alone in
# its workspace).
two_orchestrators() {
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w6:p1"}]}}'
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"},{"workspace_id":"w6","label":"home orchestrator · 2 workers"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w3:p1","workspace_id":"w3"},{"agent":"claude","name":"home-orchestrator","pane_id":"w6:p1","workspace_id":"w6"}]}}'
}

# Wait up to 5 seconds until the session log has a line that matches the regex $1.
wait_for_log() {
  local i
  for i in $(seq 50); do
    ! grep -q "$1" "$FAKE_SESSION_LOG" || return 0
    sleep 0.1
  done
  return 1
}

@test "stopping an orchestrator closes its workspace with no quit and keeps the workers" {
  one_orchestrator
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board work
  [ "$status" -eq 0 ]
  [ "$(grep -c 'agent | prompt' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -qx 'default | workspace | close | w3' "$FAKE_SESSION_LOG"
  [ "$(grep -c '^board-workers | workspace | close' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | Stopped the orchestrator of the board work' "$FAKE_SESSION_LOG"
}

@test "the stop key with one orchestrator shows a toast at once and stops it in the background" {
  one_orchestrator
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop
  [ "$status" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | Stopping the orchestrator of the board work' "$FAKE_SESSION_LOG"
  wait_for_log '^default | workspace | close | w3$'
}

@test "the stop popup closes at once and stops the picked orchestrator in the background" {
  one_orchestrator
  two_orchestrators
  run timeout 20 bash -c "printf 2 | bash '$PLUGIN_DIR/board.sh' stop-prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1] work"*"[2] home"* ]]
  grep -q '^default | notification | show | Agent tabs | --body | Stopping the orchestrator of the board home' "$FAKE_SESSION_LOG"
  wait_for_log '^default | workspace | close | w6$'
}

@test "the stop key with no orchestrator says so" {
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop
  [ "$status" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | No board orchestrator runs.' "$FAKE_SESSION_LOG"
}

@test "a stop accepts a worker view that Herdr lists as an agent" {
  one_orchestrator
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w3:p1","workspace_id":"w3"},{"agent":"dotfiles","name":"fix-x","agent_status":"idle","pane_id":"w3:p2","workspace_id":"w3"}]}}'
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board work
  [ "$status" -eq 0 ]
  grep -qx 'default | workspace | close | w3' "$FAKE_SESSION_LOG"
}

@test "stopping an orchestrator whose workspace runs another program changes nothing" {
  one_orchestrator
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w3:p1"},{"pane_id":"w3:p2"},{"pane_id":"w3:p3"}]}}'
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board work
  [ "$status" -eq 1 ]
  [ "$(grep -c 'workspace | close' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | The workspace work orchestrator has a pane that runs a program (w3:p3)' "$FAKE_SESSION_LOG"
}

@test "a stop whose close of the workspace fails says so" {
  one_orchestrator
  export FAKE_DEFAULT_CLOSE_FAIL=1
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board work
  [ "$status" -eq 1 ]
  [ "$(grep -c 'Stopped the orchestrator' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | Could not stop the orchestrator of the board work. Nothing changed.' "$FAKE_SESSION_LOG"
}

@test "stopping an orchestrator when the lookup of the orchestrator workspace fails says so and changes nothing" {
  one_orchestrator
  export FAKE_WORKSPACE_LIST_FAIL=1
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board work
  [ "$status" -eq 1 ]
  [ "$(grep -c 'workspace | close' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | Could not read the workspace work orchestrator' "$FAKE_SESSION_LOG"
}

@test "a stop waits while an open of the same board starts its orchestrator" {
  one_orchestrator
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  exec 7>>"$dir/board-work.lock"
  flock 7
  run timeout 3 bash "$PLUGIN_DIR/board.sh" stop-board work
  exec 7>&-
  [ "$status" -eq 124 ]
  # The stop made no Herdr call: the session log can be missing.
  [ "$(cat "$FAKE_SESSION_LOG" 2>/dev/null | grep -c 'workspace | close')" -eq 0 ]
}

@test "an open of a board waits while a stop of the same board runs" {
  export FAKE_DEFAULT_WS_ROOT=w3:p1
  local dir="$HOME/.local/state/board-orchestrator"
  mkdir -p "$dir"
  exec 7>>"$dir/board-work.lock"
  flock 7
  OBSIDIAN_VAULT_PATH=/vault run timeout 3 bash "$PLUGIN_DIR/board.sh" worker work
  exec 7>&-
  [ "$status" -eq 124 ]
  grep -q '^default | notification | show | Agent tabs | --body | Starting the orchestrator of the board work' "$FAKE_SESSION_LOG"
  [ "$(grep -c '| agent | start\|| workspace | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "the listener reports a view as working when its worker starts to work" {
  reviewr_beside_view
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo idle\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 working
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | --source | board-orchestrator | --agent | repo | --state | working | ' "$FAKE_SESSION_LOG"
  [ "$(grep -c 'release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "the listener reports a view as idle when its worker ends a turn" {
  reviewr_beside_view
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"working"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo working\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=done
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 done
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | .* | --state | idle | ' "$FAKE_SESSION_LOG"
}

@test "the listener keeps a red view red while its worker waits after the same turn" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"done","completion_seq":4}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo blocked\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  printf 'w9:p1 w1:p5 repo 4\n' >"$HOME/.local/state/board-orchestrator/marks-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 idle
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  [ "$(grep -c 'pane | report-agent\|release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "a view of a working worker with no reviewr in its tab is no agent" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=working
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  [ "$(grep -c 'pane | report-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "a view of a working worker with a reviewr in its tab is an agent that works" {
  reviewr_beside_view
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=working
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | .* | --state | working | ' "$FAKE_SESSION_LOG"
}

@test "a red view is an agent with no reviewr in its tab" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_AGENT_STATUS=done
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | .* | --state | blocked | ' "$FAKE_SESSION_LOG"
}

@test "the listener releases the view of a worker that works when no reviewr is open in its tab" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo idle fix-x\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 working
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^default | pane | release-agent | w1:p5 | --source | board-orchestrator | --agent | repo | ' "$FAKE_SESSION_LOG"
  [ "$(grep -c 'pane | report-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "the pane.closed hook releases a view that is no red when its reviewr is closed" {
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo idle fix-x\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle
  run bash "$PLUGIN_DIR/dispatch.sh" views-sync
  [ "$status" -eq 0 ]
  grep -q '^default | pane | release-agent | w1:p5 | --source | board-orchestrator | --agent | repo | ' "$FAKE_SESSION_LOG"
}

@test "the pane.closed hook keeps a red view" {
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo blocked fix-x\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  printf 'w9:p1 w1:p5 repo 4\n' >"$HOME/.local/state/board-orchestrator/marks-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4
  run bash "$PLUGIN_DIR/dispatch.sh" views-sync
  [ "$status" -eq 0 ]
  [ "$(grep -c 'release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "the pane.closed hook keeps a view while another reviewr is open in its tab" {
  reviewr_beside_view
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo idle fix-x\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle
  run bash "$PLUGIN_DIR/dispatch.sh" views-sync
  [ "$status" -eq 0 ]
  [ "$(grep -c 'release-agent' "$FAKE_LOG")" -eq 0 ]
}

@test "the manifest runs views-sync when a pane closes or exits" {
  grep -A2 'on = "pane.closed"' "$PLUGIN_DIR/herdr-plugin.toml" | grep -q 'views-sync'
  grep -A2 'on = "pane.exited"' "$PLUGIN_DIR/herdr-plugin.toml" | grep -q 'views-sync'
}

@test "reviewr in a worker view reports the view as an agent with the worker name at once" {
  make_repo >/dev/null
  worktree=$(make_worktree)
  mkdir -p "$(dirname "$(wt_file)")" "$HOME/.local/state/board-orchestrator"
  printf '%s\n' "$worktree" >"$(dirname "$(wt_file)")/board-workers.w9_p1"
  printf 'w9:p1 w1:p1 repo - fix-x\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_of_worker
  export FAKE_CWD="$HOME" FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t9"},{"pane_id":"w1:p6","tab_id":"w1:t9"}]}}'
  export FAKE_REVIEWR_PANES=w1:p6
  run bash "$PLUGIN_DIR/reviewr.sh"
  [ "$status" -eq 0 ]
  wait_for_log '^default | agent | rename | w1:p1 | fix-x'
  grep -q '^default | pane | report-agent | w1:p1 | .* | --state | working | ' "$FAKE_SESSION_LOG"
}

@test "the listener ignores a red mark of an older view and reports the new view" {
  reviewr_beside_view
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"done","completion_seq":4}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo blocked\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  printf 'w9:p1 w1:p4 repo 4\n' >"$HOME/.local/state/board-orchestrator/marks-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=idle FAKE_COMPLETION_SEQS=4
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 idle
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | .* | --state | idle | ' "$FAKE_SESSION_LOG"
  grep -q '^w9:p1 w1:p5 ' "$HOME/.local/state/board-orchestrator/views-board-workers"
}

@test "dispatch show writes the red mark before it reports the view" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5
  export FAKE_SNAPSHOT_MARKS="$HOME/.local/state/board-orchestrator/marks-board-workers"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  grep -q '^w1:p9 w1:p5 ' "$FAKE_LOG.marks-at-report"
}

@test "the listener keeps a view when the check of its process fails once" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo idle\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working FAKE_PROCESS_INFO_FAIL=1
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 working
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^w9:p1 w1:p5 ' "$HOME/.local/state/board-orchestrator/views-board-workers"
}

@test "dispatch show with need keeps no red mark when the report fails" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 FAKE_REPORT_FAIL=1
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9 need
  [ "$status" -eq 0 ]
  [ "$(grep -c 'w1:p9' "$HOME/.local/state/board-orchestrator/marks-board-workers" 2>/dev/null)" -eq 0 ]
}

@test "the listener keeps the red mark when the report of the new state fails" {
  reviewr_beside_view
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"working"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo blocked\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  printf 'w9:p1 w1:p5 repo 4\n' >"$HOME/.local/state/board-orchestrator/marks-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working FAKE_REPORT_FAIL=1
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 working
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^w9:p1 w1:p5 repo 4' "$HOME/.local/state/board-orchestrator/marks-board-workers"
}

@test "the listener gives a view its worker name again when it reports it after a release" {
  reviewr_beside_view
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"working"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo - fix-x\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p5 w9:p1
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 working
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^default | pane | report-agent | w1:p5 | .* | --state | working | ' "$FAKE_SESSION_LOG"
  grep -qx 'default | agent | rename | w1:p5 | fix-x' "$FAKE_SESSION_LOG"
}

@test "the listener releases the view of a worker that is gone" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p3 w1:p6 repo idle\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  view_runs w1:p6 w9:p3
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  grep -q '^default | pane | release-agent | w1:p6 | --source | board-orchestrator | --agent | repo | ' "$FAKE_SESSION_LOG"
}

@test "the listener forgets a view that no longer shows its worker" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w9:p1 w1:p5 repo idle\n' >"$HOME/.local/state/board-orchestrator/views-board-workers"
  export FAKE_AGENT_KIND=claude FAKE_AGENT_STATUS=working
  status_event "$BATS_TEST_TMPDIR/ev1" w9:p1 working
  export FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  run timeout 20 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  [ "$(grep -c 'pane | report-agent' "$FAKE_LOG")" -eq 0 ]
  [ "$(grep -c 'w9:p1' "$HOME/.local/state/board-orchestrator/views-board-workers")" -eq 0 ]
}

@test "the listener reports nothing for a board whose orchestrator was stopped" {
  count_watch_board '[{"pane_id":"w9:p1","workspace_id":"w9","agent":"claude","agent_status":"idle"}]'
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w9","label":"home workers"}]}}'
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[]}}' FAKE_NC_EVENTS="$BATS_TEST_TMPDIR/ev1"
  : >"$BATS_TEST_TMPDIR/ev1"
  run timeout 10 bash "$PLUGIN_DIR/dispatch.sh" count-watch
  [ "$status" -eq 0 ]
  [ "$(grep -c 'report-agent\|release-agent\|report-metadata' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "an idle worker whose background agent still works counts as working" {
  orchestrator_with_workers "" 2 idle
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  printf '%s\n' '❯' '  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent · ↓ to manage' '  ● main' \
    '  ◯ general-purpose  Linting my-app README.md        1m 18s · ↓ 66.4k tokens' >"$FAKE_PANE_SCREENS/w3:p1"
  printf '%s\n' '❯' '  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent' >"$FAKE_PANE_SCREENS/w3:p2"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=2 workers \| --token \| working=1 working \| --seq' "$FAKE_SESSION_LOG"
}

@test "an idle worker with a running background shell counts as working" {
  orchestrator_with_workers "" 1 idle
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  printf '%s\n' '────' '❯' '────' '  ⏵⏵ auto mode on · 3 shells · ← 2 agents · ↓ to manage' >"$FAKE_PANE_SCREENS/w3:p1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| --token \| working=1 working \| --seq' "$FAKE_SESSION_LOG"
}

@test "a done worker with a running background shell counts as working" {
  orchestrator_with_workers "" 1 done
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  printf '%s\n' '✻ Crunched for 1s · done 8:25 AM · 1 shell still running' '' \
    '─────────────── Find why the db backups fail ─' '❯' '──────────────────────────────' \
    '  ⏵⏵ auto mode on · 1 shell · ← 2 agents · ↓ to manage' >"$FAKE_PANE_SCREENS/w3:p1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| --token \| working=1 working \| --seq' "$FAKE_SESSION_LOG"
}

@test "a worker whose transcript talks of 1 shell above the input box does not count as working" {
  orchestrator_with_workers "" 1 done
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  printf '%s\n' '● I start 1 shell · then I wait' '────' '❯' '────' \
    '  ⏵⏵ auto mode on (shift+tab to cycle) · ← 2 agents' >"$FAKE_PANE_SCREENS/w3:p1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| --clear-token \| working \| --seq' "$FAKE_SESSION_LOG"
}

@test "a worker whose transcript talks of 1 agent above the footer does not count as working" {
  orchestrator_with_workers "" 1 done
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  { printf '%s\n' '● I wait for 1 agent · then I push'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'line %s\n' "$i"; done
    printf '%s\n' '❯' '  ⏵⏵ auto mode on · ↓ to manage'; } >"$FAKE_PANE_SCREENS/w3:p1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| --clear-token \| working \| --seq' "$FAKE_SESSION_LOG"
}

@test "a working worker and a blocked worker are not read with pane read" {
  orchestrator_with_workers "" 1 working
  FAKE_HIDDEN_AGENTS_JSON=$(jq -c '.result.agents += [{pane_id: "w3:p7", agent: "claude", agent_status: "blocked", workspace_id: "w3"}]' <<<"$FAKE_HIDDEN_AGENTS_JSON")
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  [ "$(grep -c 'pane | read' "$FAKE_LOG")" -eq 0 ]
  grep -qE 'workers=2 workers \| --token \| working=1 working' "$FAKE_SESSION_LOG"
}

@test "an idle worker whose footer shows 1 agent with no agent list does not count as working" {
  orchestrator_with_workers "" 1 idle
  export FAKE_PANE_SCREENS="$BATS_TEST_TMPDIR/screens"
  mkdir -p "$FAKE_PANE_SCREENS"
  printf '%s\n' '❯' '──────────────────────────────────' \
    '  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent' >"$FAKE_PANE_SCREENS/w3:p1"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" workers home
  [ "$status" -eq 0 ]
  grep -qE '^default \| workspace \| report-metadata \| w1 \| --source \| board-orchestrator \| --token \| workers=1 worker \| --clear-token \| working \| --seq' "$FAKE_SESSION_LOG"
}

# Make the temp vault of a log test, with the folders of a real vault.
log_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Dev Logs" "$OBSIDIAN_VAULT_PATH/Daily"
  LOG_NOTE="$OBSIDIAN_VAULT_PATH/Dev Logs/$(date +%F) - work (board orchestrator).md"
  DAILY="$OBSIDIAN_VAULT_PATH/Daily/$(date +%F).md"
}

# Write the text $1 of a log line to a new file and print its path.
log_file() {
  local f
  f=$(mktemp "$BATS_TEST_TMPDIR/log.XXXXXX")
  printf '%s\n' "$1" >"$f"
  printf '%s\n' "$f"
}

@test "an orchestrator log line goes under Log of a new daily board note" {
  log_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'Fix the parser — done; PR #3')"
  [ "$status" -eq 0 ]
  [ -f "$LOG_NOTE" ]
  grep -qx "date: $(date +%F)" "$LOG_NOTE"
  grep -qx 'type: devlog' "$LOG_NOTE"
  grep -qx 'tags: \[devlog, board-orchestrator, work\]' "$LOG_NOTE"
  grep -qx 'ai-first: true' "$LOG_NOTE"
  grep -qx 'board: "\[\[Boards/work\]\]"' "$LOG_NOTE"
  grep -qx '## For future agent' "$LOG_NOTE"
  [ "$(tail -2 "$LOG_NOTE" | head -1)" = '## Log' ]
  tail -1 "$LOG_NOTE" | grep -qE '^- [0-9]{2}:[0-9]{2} Fix the parser — done; PR #3$'
}

@test "a second orchestrator log line goes after the first one" {
  log_vault
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'first card — done')"
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'second card — waits for the user')"
  [ "$(grep -c '^## Log$' "$LOG_NOTE")" -eq 1 ]
  tail -2 "$LOG_NOTE" | head -1 | grep -q 'first card — done$'
  tail -1 "$LOG_NOTE" | grep -q 'second card — waits for the user$'
}

@test "the orchestrator log adds its link at the end of the Work section of the daily note" {
  log_vault
  printf -- '---\ntype: daily\n---\n\n## Work\n\n- earlier work\n\n## Tasks\n\n- [ ] a task\n' >"$DAILY"
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  link="- [[Dev Logs/$(date +%F) - work (board orchestrator)]]"
  [ "$(grep -cxF -- "$link" "$DAILY")" -eq 1 ]
  [ "$(grep -nxF -- "$link" "$DAILY" | cut -d: -f1)" -eq 8 ]
  [ "$(sed -n 7p "$DAILY")" = '- earlier work' ]
  [ "$(sed -n 10p "$DAILY")" = '## Tasks' ]
  [ "$(tail -1 "$DAILY")" = '- [ ] a task' ]
}

@test "the orchestrator log adds its link to the daily note only once" {
  log_vault
  printf -- '## Work\n\n- earlier work\n' >"$DAILY"
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'another card — done')"
  [ "$(grep -c 'work (board orchestrator)' "$DAILY")" -eq 1 ]
}

@test "the orchestrator log appends its link to a daily note with no Work section" {
  log_vault
  printf -- '---\ntype: daily\n---\n\n## Tasks\n\n- [ ] a task\n' >"$DAILY"
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  [ "$(tail -1 "$DAILY")" = "- [[Dev Logs/$(date +%F) - work (board orchestrator)]]" ]
  grep -qx -- '- \[ \] a task' "$DAILY"
}

@test "the orchestrator log creates no daily note" {
  log_vault
  bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  [ ! -e "$DAILY" ]
}

@test "the orchestrator log with no text gives the usage" {
  log_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" log work
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh log BOARD FILE"* ]]
}

@test "the orchestrator log with no vault path fails" {
  unset OBSIDIAN_VAULT_PATH
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no vault path"* ]]
}

@test "a card title with a backtick and a dollar sign goes into the log as it is" {
  log_vault
  f=$(log_file 'Fix `date` and $HOME — done')
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" log work "$f"
  [ "$status" -eq 0 ]
  [[ "$(tail -1 "$LOG_NOTE")" == *' Fix `date` and $HOME — done' ]]
}

@test "a log text on two lines stays one log line" {
  log_vault
  f=$(log_file $'first part\nsecond part')
  bash "$PLUGIN_DIR/dispatch.sh" log work "$f"
  tail -1 "$LOG_NOTE" | grep -qE '^- [0-9]{2}:[0-9]{2} first part second part$'
}

@test "the orchestrator log with a missing text file fails and writes nothing" {
  log_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" log work "$BATS_TEST_TMPDIR/none"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"missing or empty"* ]]
  [ ! -e "$LOG_NOTE" ]
}

@test "a report summary gives the first line, the Result and Vault changes sections and the refused calls" {
  r="$BATS_TEST_TMPDIR/report.md"
  printf '%s\n' 'STATUS: REFUSED' '# Check fees' '' '## Result' 'Fees are ok.' 'REFUSED: git fetch' '' \
    '## Details' 'long detail' 'REFUSED: gh pr list' '' '## Vault changes' '- Boards/work.md: old -> new' >"$r"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" report "$r"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'STATUS: REFUSED' ]
  [[ "$output" == *$'## Result\nFees are ok.'* ]]
  [[ "$output" == *$'## Vault changes\n- Boards/work.md: old -> new'* ]]
  [[ "$output" == *'REFUSED: gh pr list'* ]]
  [[ "$output" != *'long detail'* ]]
  [ "${lines[-1]}" = "full report: $r (13 lines)" ]
}

@test "a report with no Result section gives its first 40 lines" {
  r="$BATS_TEST_TMPDIR/report.md"
  { printf 'RESULT: DONE\n'; for i in $(seq 2 50); do printf 'line %s\n' "$i"; done; } >"$r"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" report "$r"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 41 ]
  [ "${lines[39]}" = 'line 40' ]
  [ "${lines[40]}" = "full report: $r (50 lines)" ]
}

@test "a long Result section of a report is cut at 60 lines with a note" {
  r="$BATS_TEST_TMPDIR/report.md"
  { printf 'RESULT: DONE\n## Result\n'; for i in $(seq 1 80); do printf 'result %s\n' "$i"; done; } >"$r"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" report "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'result 59\n'* ]]
  [[ "$output" != *'result 60'* ]]
  [[ "$output" == *'section cut: 21 more lines'* ]]
}

@test "a report summary with no report file fails" {
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" report "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh report PATH"* ]]
}

@test "a task worker footer asks for a short Result section" {
  printf 'Do it.\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "Fix X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  grep -q 'After the first line, write a section ## Result of at most 10 lines' "$FAKE_LOG"
}

# Make the temp vault of a run-add test, with a task note and a report.
run_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Tasks"
  TASK="$OBSIDIAN_VAULT_PATH/Tasks/Check.md"
  REPORT="$BATS_TEST_TMPDIR/report.md"
  printf -- 'STATUS: OK\n\n# Checks\n\n| a | b |\n\n## Notes\n\n- all good\n' >"$REPORT"
  TODAY=$(date +%F)
}

@test "the first run of a recurring card adds a Runs section at the end of the task note" {
  run_vault
  printf -- '---\ntype: task\n---\n\n## Prompt\n\ndo it\n' >"$TASK"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$status" -eq 0 ]
  [ "$output" = "run-add: Tasks/Check.md $TODAY" ]
  expected=$(printf -- '---\ntype: task\n---\n\n## Prompt\n\ndo it\n\n## Runs\n\n### %s\n\nSTATUS: OK\n\n#### Checks\n\n| a | b |\n\n##### Notes\n\n- all good' "$TODAY")
  [ "$(cat "$TASK")" = "$expected" ]
}

@test "a run goes at the end of a Runs section that is the last section" {
  run_vault
  printf -- '## Prompt\n\ndo it\n\n## Runs\n\n### 2026-01-01\n\nSTATUS: OK\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(sed -n 9p "$TASK")" = 'STATUS: OK' ]
  [ "$(sed -n 10,11p "$TASK")" = "$(printf -- '\n### %s' "$TODAY")" ]
  [ "$(tail -1 "$TASK")" = '- all good' ]
  [ "$(grep -c '^## Runs$' "$TASK")" -eq 1 ]
}

@test "a run goes after the last run when a section follows Runs" {
  run_vault
  printf -- '## Runs\n\n### 2026-01-01\n\nold run\n\n## Links\n\n- a link\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -n "^### $TODAY\$" "$TASK" | cut -d: -f1)" -eq 7 ]
  [ "$(sed -n 5,6p "$TASK")" = "$(printf 'old run\n')" ]
  [ "$(grep -B2 '^## Links$' "$TASK" | head -1)" = '- all good' ]
  [ "$(tail -1 "$TASK")" = '- a link' ]
}

@test "a second record of the same card on the same day replaces the run of that day" {
  run_vault
  printf -- '## Runs\n\n### 2026-01-01\n\nold run\n\n### %s\n\nSTATUS: STOP\n\n#### First\n\n## Links\n\n- a link\n' "$TODAY" >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -c "^### $TODAY\$" "$TASK")" -eq 1 ]
  [ "$(grep -c 'STATUS: STOP' "$TASK")" -eq 0 ]
  [ "$(grep -c 'First' "$TASK")" -eq 0 ]
  grep -qx 'old run' "$TASK"
  grep -qx '#### Checks' "$TASK"
  [ "$(tail -1 "$TASK")" = '- a link' ]
}

@test "a run keeps a heading inside a code block of the report" {
  run_vault
  printf -- 'RESULT: DONE\n\n```\n# a shell comment\n```\n' >"$REPORT"
  printf -- '## Prompt\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  grep -qx 'RESULT: DONE' "$TASK"
  grep -qx '# a shell comment' "$TASK"
}

@test "a run after a fenced line that starts with ## goes after the fence, at the end of Runs" {
  run_vault
  printf -- '## Runs\n\n### 2026-01-01\n\n```\n## a quoted note\n### a quoted run\n```\n\nold end\n\n## Links\n\n- a link\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -n "^### $TODAY\$" "$TASK" | cut -d: -f1)" -eq 12 ]
  [ "$(sed -n 10p "$TASK")" = 'old end' ]
  grep -qx '## a quoted note' "$TASK"
  grep -qx '### a quoted run' "$TASK"
  [ "$(tail -1 "$TASK")" = '- a link' ]
}

@test "a second record on the same day replaces the whole run of that day, past a fenced ### line" {
  run_vault
  printf -- '## Runs\n\n### %s\n\n~~~\n### quoted\n~~~\n\nold tail\n\n## Links\n' "$TODAY" >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -c -e quoted -e 'old tail' "$TASK")" -eq 0 ]
  [ "$(grep -c "^### $TODAY\$" "$TASK")" -eq 1 ]
  [ "$(tail -1 "$TASK")" = '## Links' ]
}

@test "a run sets the updated field of the task note to today" {
  run_vault
  printf -- '---\ntype: task\nupdated: 2026-01-01\n---\n\n## Prompt\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(sed -n 1,4p "$TASK")" = "$(printf -- '---\ntype: task\nupdated: %s\n---' "$TODAY")" ]
}

@test "a run with no report gives the usage" {
  run_vault
  printf -- '## Prompt\n' >"$TASK"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh run-add NOTE REPORT"* ]]
}

@test "a run for a task note that is not in the vault fails" {
  run_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/None.md "$REPORT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no task note"* ]]
}

@test "a run with no vault path fails" {
  run_vault
  unset OBSIDIAN_VAULT_PATH
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no vault path"* ]]
}

# Make the temp vault of a note-add test: a board with a long card at line 7 that links
# Tasks/Check.md, a card at line 9 that links another note, and a card with no context.
note_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Tasks" "$OBSIDIAN_VAULT_PATH/Boards"
  TASK="$OBSIDIAN_VAULT_PATH/Tasks/Check.md"
  BOARD="$OBSIDIAN_VAULT_PATH/Boards/main.md"
  TODAY=$(date +%F)
  printf -- '---\nkanban-plugin: board\n---\n\n## ⏳ Waiting On\n\n- [ ] 🟡 **[alpha] Check**\n\tPR 12 pushed, head `abc`. [[Tasks/Check]] [[Projects/alpha]]\n- [ ] 🟢 **[alpha] Other**\n\tOther text. [[Tasks/Other]]\n- [ ] 🟢 **[alpha] Bare**\n' >"$BOARD"
}

@test "the long text of a card goes to the end of the Notes section of its task note" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Notes\n\n- old note\n\n## Runs\n\n### 2026-01-01\n' >"$TASK"
  cp "$BOARD" "$BATS_TEST_TMPDIR/board-before"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 0 ]
  [ "$output" = "note-add: Tasks/Check.md $TODAY" ]
  expected=$(printf -- '## Notes\n\n- old note\n\n### %s, from the board\n\nPR 12 pushed, head `abc`. [[Tasks/Check]] [[Projects/alpha]]\n\n## Runs\n\n### 2026-01-01' "$TODAY")
  [ "$(sed -n '5,$p' "$TASK")" = "$expected" ]
  cmp "$BOARD" "$BATS_TEST_TMPDIR/board-before"
}

@test "a task note with no Notes section gets one at its end" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Prompt\n\ndo it\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  expected=$(printf -- '## Prompt\n\ndo it\n\n## Notes\n\n### %s, from the board\n\nPR 12 pushed, head `abc`. [[Tasks/Check]] [[Projects/alpha]]' "$TODAY")
  [ "$(sed -n '5,$p' "$TASK")" = "$expected" ]
}

@test "a card text of more lines keeps its lines, with no tab at the start" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\tFirst line.\n\t\tSecond line. [[Tasks/Check]]\n' >"$BOARD"
  bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(tail -2 "$TASK")" = "$(printf 'First line.\n\tSecond line. [[Tasks/Check]]')" ]
}

@test "a Notes heading in a code block of an old run is not the Notes section" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Runs\n\n~~~\n## Notes\n~~~\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(grep -c '^## Notes$' "$TASK")" -eq 2 ]
  [ "$(sed -n 10,12p "$TASK")" = "$(printf -- '\n## Notes\n')" ]
}

@test "a card text with a backslash goes to the task note as it is" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\tThe path C:\\new\\tmp. [[Tasks/Check]]\n' >"$BOARD"
  bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(tail -1 "$TASK")" = 'The path C:\new\tmp. [[Tasks/Check]]' ]
}

@test "the copy of a card text sets the updated field of the task note to today" {
  note_vault
  printf -- '---\ntype: task\nupdated: 2026-01-01\n---\n' >"$TASK"
  bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(sed -n 3p "$TASK")" = "updated: $TODAY" ]
}

@test "a line number that moved to a context line after a user edit changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 8 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no card [alpha] Check at line 8"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a card that links its task note and a related task note gives its text to its own note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\tSee [[Tasks/Other]] first. [[Tasks/Check]]\n' >"$BOARD"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$TASK")" = 'See [[Tasks/Other]] first. [[Tasks/Check]]' ]
}

@test "a card that links another task note changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 9 "[alpha] Other"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"links Tasks/Other"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a card with no context line changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 11 "[alpha] Bare"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no context line"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a copy to a task note that is not in the vault fails" {
  note_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no task note"* ]]
}

@test "a copy from a board that is not in the vault fails" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md other 7 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no board other"* ]]
}

@test "a copy with no line number gives the usage" {
  note_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh note-add NOTE BOARD LINE TITLE"* ]]
}

@test "a copy with no title gives the usage" {
  note_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh note-add NOTE BOARD LINE TITLE"* ]]
}

@test "a card of the user that took the line of the card after an edit changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  # The user added a card at the top: the card Check moved from line 7 to line 9.
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟢 **[beta] User card**\n\tPrivate text. [[Projects/beta]]\n- [ ] 🟡 **[alpha] Check**\n\tLong text. [[Tasks/Check]]\n' >"$BOARD"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no card [alpha] Check at line 7"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a heading in a card text goes under the entry of the day, not beside it" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Notes\n\n- old\n\n## Runs\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\t## Plan [[Tasks/Check]]\n' >"$BOARD"
  bash "$PLUGIN_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  grep -qx '##### Plan \[\[Tasks/Check\]\]' "$TASK"
  [ "$(grep -c '^## ' "$TASK")" -eq 2 ]
}

@test "an orchestrator claude reads its skill again after a compact" {
  export HERDR_WORKSPACE_ID=w8 HERDR_PANE_ID=w8:p1 HERDR_ENV=1 FAKE_AGENT_KIND=claude FAKE_NAME=home-orchestrator
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w8","label":"home orchestrator · 2 workers"}]}}'
  run bash "$PLUGIN_DIR/compact-orchestrator.sh" </dev/null
  [ "$status" -eq 0 ]
  context=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
  [[ "$context" == *"board home"* ]]
  [[ "$context" == *"~/.claude/skills/board-orchestrator/SKILL.md"* ]]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = SessionStart ]
  grep -qx 'agent | get | w8:p1' "$FAKE_LOG"
}

@test "a worker claude gets no orchestrator text after a compact" {
  export HERDR_SESSION=board-workers HERDR_WORKSPACE_ID=w9 HERDR_ENV=1 FAKE_AGENT_KIND=claude FAKE_NAME=fix-x
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w9","label":"home workers"}]}}'
  run bash "$PLUGIN_DIR/compact-orchestrator.sh" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a claude in a workspace home orchestrator of the hidden session gets no orchestrator text after a compact" {
  export HERDR_SESSION=board-workers HERDR_WORKSPACE_ID=w8 HERDR_PANE_ID=w8:p1 HERDR_ENV=1 FAKE_AGENT_KIND=claude FAKE_NAME=home-orchestrator
  export FAKE_HIDDEN_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w8","label":"home orchestrator"}]}}'
  run bash "$PLUGIN_DIR/compact-orchestrator.sh" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a claude with another name in the orchestrator workspace gets no orchestrator text after a compact" {
  export HERDR_WORKSPACE_ID=w8 HERDR_PANE_ID=w8:p2 HERDR_ENV=1 FAKE_AGENT_KIND=claude FAKE_NAME=notes
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w8","label":"home orchestrator"}]}}'
  run bash "$PLUGIN_DIR/compact-orchestrator.sh" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a stop leaves a user claude alone when the orchestrator of the board has exited" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"fix-bug","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w3:p1"}]}}'
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board work
  [ "$status" -eq 1 ]
  [ "$(grep -c 'workspace | close' "$FAKE_SESSION_LOG")" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | No orchestrator runs for the board work.' "$FAKE_SESSION_LOG"
}

@test "the stop key says no orchestrator runs when only a user claude runs in an orchestrator workspace" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"fix-bug","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop
  [ "$status" -eq 0 ]
  grep -q '^default | notification | show | Agent tabs | --body | No board orchestrator runs.' "$FAKE_SESSION_LOG"
}

@test "an open starts an orchestrator when only a user claude runs in the workspace" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"fix-bug","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  export FAKE_TAB_ROOT=w3:p4
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker work
  [ "$status" -eq 0 ]
  grep -q '^default | agent | start | claude-start-w3-p4 | --kind | claude | --pane | w3:p4 ' "$FAKE_SESSION_LOG"
  grep -qx 'default | agent | prompt | w3:p4 | /board-orchestrator work' "$FAKE_SESSION_LOG"
  [ "$(grep -c 'agent | focus | w3:p1' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "an open names the orchestrator of a board with capitals with its slug" {
  export FAKE_DEFAULT_WS_ROOT=w3:p1
  OBSIDIAN_VAULT_PATH=/vault run bash "$PLUGIN_DIR/board.sh" worker Work
  [ "$status" -eq 0 ]
  grep -qx 'default | agent | rename | w3:p1 | work-orchestrator' "$FAKE_SESSION_LOG"
}

@test "a stop finds the orchestrator of a board with capitals in its name" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"Work orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w3:p1"}]}}'
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board Work
  [ "$status" -eq 0 ]
  grep -qx 'default | workspace | close | w3' "$FAKE_SESSION_LOG"
}

@test "a stop finds the orchestrator of a board with a long name by its cut name" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"A Very Long Board Name For Testing orchestrator"}]}}'
  export FAKE_AGENTS_JSON='{"result":{"agents":[{"agent":"claude","name":"a-very-long-board-name-for-2","pane_id":"w3:p1","workspace_id":"w3"}]}}'
  export FAKE_PANES_JSON='{"result":{"panes":[{"pane_id":"w3:p1"}]}}'
  run timeout 20 bash "$PLUGIN_DIR/board.sh" stop-board "A Very Long Board Name For Testing"
  [ "$status" -eq 0 ]
  grep -qx 'default | workspace | close | w3' "$FAKE_SESSION_LOG"
}

@test "an open that waited for another open of the same board focuses its orchestrator and starts none" {
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w3","label":"work orchestrator"}]}}'
  export FAKE_AGENTS_FILE="$BATS_TEST_TMPDIR/agents.json"
  printf '{"result":{"agents":[]}}\n' >"$FAKE_AGENTS_FILE"
  local dir="$HOME/.local/state/board-orchestrator" pid
  mkdir -p "$dir"
  exec 7>>"$dir/board-work.lock"
  flock 7
  OBSIDIAN_VAULT_PATH=/vault timeout 20 bash "$PLUGIN_DIR/board.sh" worker work 7>&- &
  pid=$!
  wait_for_log 'Starting the orchestrator of the board work'
  # The first open ends: its claude now has the orchestrator name.
  printf '{"result":{"agents":[{"agent":"claude","name":"work-orchestrator","pane_id":"w3:p1","workspace_id":"w3"}]}}\n' >"$FAKE_AGENTS_FILE"
  exec 7>&-
  wait "$pid"
  grep -qx 'default | agent | focus | w3:p1' "$FAKE_SESSION_LOG"
  [ "$(grep -c '| agent | start\|| workspace | create\|| tab | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

@test "an orchestrator claude of a board with a capital reads its skill again after a compact" {
  export HERDR_WORKSPACE_ID=w8 HERDR_PANE_ID=w8:p1 HERDR_ENV=1 FAKE_AGENT_KIND=claude FAKE_NAME=home-orchestrator
  export FAKE_WORKSPACES_JSON='{"result":{"workspaces":[{"workspace_id":"w8","label":"Home orchestrator"}]}}'
  run bash "$PLUGIN_DIR/compact-orchestrator.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"board Home"* ]]
}

@test "dispatch start in a pane of the hidden session exits 2 before any herdr call" {
  export HERDR_SESSION=board-workers
  printf 'x\n' >"$BATS_TEST_TMPDIR/p.md"
  allow_push "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" start task "$BATS_TEST_TMPDIR" "X" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  [ "$stderr" = "dispatch: start runs only in the orchestrator, not in the hidden session board-workers." ]
  [ ! -s "$FAKE_LOG" ]
}

@test "dispatch show in a pane of the hidden session exits 2 for a worker with no board" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 HERDR_SESSION=board-workers
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 2 ]
  # The refusal makes no Herdr call: the session log can be missing.
  [ "$(cat "$FAKE_SESSION_LOG" 2>/dev/null | grep -c '| tab | create')" -eq 0 ]
}

@test "dispatch show in a pane of the hidden session fails when the orchestrator workspace of the board is gone" {
  export FAKE_AGENT_KIND=claude FAKE_TAB_ROOT=w1:p5 HERDR_SESSION=board-workers
  mkdir -p "$HOME/.local/state/board-orchestrator"
  printf 'w1:p9\ttask\thome\t/r.md\n' >"$HOME/.local/state/board-orchestrator/workers-board-workers"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" show w1:p9
  [ "$status" -eq 1 ]
  [ "$(grep -c '^default | workspace | create\|^default | tab | create' "$FAKE_SESSION_LOG")" -eq 0 ]
}

# Make the temp vault of an inbox-clear test, with one phone message and one task note.
inbox_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/_inbox" "$OBSIDIAN_VAULT_PATH/Tasks"
  MESSAGE="$OBSIDIAN_VAULT_PATH/_inbox/2026-11-04-173424.md"
  printf 'check the PR 1219\n' >"$MESSAGE"
  printf 'a task\n' >"$OBSIDIAN_VAULT_PATH/Tasks/X.md"
}

@test "a phone message that became a card leaves the inbox" {
  inbox_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" inbox-clear _inbox/2026-11-04-173424.md
  [ "$status" -eq 0 ]
  [ "$output" = 'inbox-clear: _inbox/2026-11-04-173424.md' ]
  [ ! -e "$MESSAGE" ]
}

@test "a phone message that the orchestrator of another board already cleared is gone" {
  inbox_vault
  rm "$MESSAGE"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" inbox-clear _inbox/2026-11-04-173424.md
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is gone"* ]]
}

@test "inbox-clear keeps a note outside the inbox" {
  inbox_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" inbox-clear Tasks/X.md
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh inbox-clear _inbox/NAME.md"* ]]
  [ -f "$OBSIDIAN_VAULT_PATH/Tasks/X.md" ]
}

@test "inbox-clear keeps a note that a path climbs out of the inbox to" {
  inbox_vault
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" inbox-clear _inbox/../Tasks/X.md
  [ "$status" -eq 2 ]
  [ -f "$OBSIDIAN_VAULT_PATH/Tasks/X.md" ]
}

@test "inbox-clear keeps a file in the inbox that is not a message" {
  inbox_vault
  printf 'half written\n' >"$OBSIDIAN_VAULT_PATH/_inbox/.syncthing.x.md.tmp"
  run --separate-stderr bash "$PLUGIN_DIR/dispatch.sh" inbox-clear _inbox/.syncthing.x.md.tmp
  [ "$status" -eq 2 ]
  [ -f "$OBSIDIAN_VAULT_PATH/_inbox/.syncthing.x.md.tmp" ]
}
