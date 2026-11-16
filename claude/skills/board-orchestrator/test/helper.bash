# shellcheck shell=bash
# Common setup for the board-orchestrator tests.

# shellcheck disable=SC2034 # Used by the test files.
SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

hc_setup() {
  # On macOS, TMPDIR is under /var, a link to /private/var, and pwd -P in the scripts
  # gives /private/var. Use the real path, so that the paths in the log match.
  BATS_TEST_TMPDIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
  export HC_BIN="${FAKES:-$BATS_TEST_DIRNAME}/fake-hc"
  export HERDR_APP_BIN="${FAKES:-$BATS_TEST_DIRNAME}/fake-herdr-app"
  mkdir -p "$HOME" "$FAKE_DIR"
  : >"$FAKE_LOG"
  unset HC_TERMINAL_ID HERDR_ENV HERDR_WORKSPACE_ID HERDR_PANE_ID OBSIDIAN_VAULT_PATH FAKE_HC_FAIL FAKE_APP_FAIL
}

setup() { hc_setup; }

# fake_terminal ADDR BOARD ROLE [FOREGROUND [EXTRA_LABELS_JSON]]: a live hc terminal.
fake_terminal() {
  local addr=$1 board=$2 role=$3 fg=${4:-claude} extra=${5:-'{}'}
  jq -n --arg a "$addr" --arg b "$board" --arg r "$role" --arg fg "$fg" --argjson x "$extra" \
    '{address:$a, state:"live", foreground:{name:$fg}, labels:({board:$b, "board.role":$r} + $x)}' \
    >"$FAKE_DIR/hc-get-$addr.json"
}

# calls PATTERN: the logged calls that match PATTERN (grep -E).
calls() { grep -E -- "$1" "$FAKE_LOG" || true; }

# run_args [N]: the arguments of the Nth hc run call (default 1), one for each element
# of the array RUN_ARGS.
run_args() {
  mapfile -d '' RUN_ARGS <"$FAKE_DIR/hc-run-${1:-1}.args"
}

# has_arg VALUE: exit 0 when RUN_ARGS has VALUE.
has_arg() {
  local a
  for a in "${RUN_ARGS[@]}"; do [ "$a" != "$1" ] || return 0; done
  return 1
}

# arg_after FLAG: the element after the first FLAG in RUN_ARGS.
arg_after() {
  local i
  for i in "${!RUN_ARGS[@]}"; do
    [ "${RUN_ARGS[$i]}" != "$1" ] || { printf '%s\n' "${RUN_ARGS[$((i + 1))]}"; return 0; }
  done
  return 1
}

# orchestrator ADDR BOARD: the caller is the orchestrator ADDR of BOARD.
orchestrator() {
  export HC_TERMINAL_ID=$1
  fake_terminal "$1" "$2" orchestrator
}

# repo_with_push_policy DIR: a repo folder with an allow push policy.
repo_with_push_policy() {
  mkdir -p "$1/.claude"
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$1/.claude/settings.local.json"
}

# set_status ADDR STATE: the agent status of the fake terminal ADDR.
set_status() {
  local f="$FAKE_DIR/hc-get-$1.json"
  jq --arg s "$2" '.status = {app: "claude-code", state: $s}' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

# record_worker ADDR BOARD SESSION [REPORT]: a line in the workers record.
record_worker() {
  local dir="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$dir" "$BATS_TEST_TMPDIR/repo"
  printf '%s\ttask\t%s\t%s\t%s\t%s\tfix-login\n' "$1" "$2" "${4:-$dir/fix-login-1.md}" "$3" \
    "$BATS_TEST_TMPDIR/repo" >>"$dir/workers"
}

# live_worker ADDR BOARD SESSION: a live worker terminal with its record.
live_worker() {
  fake_terminal "$1" "$2" worker claude "{\"board.session\":\"$3\"}"
  record_worker "$1" "$2" "$3"
}
