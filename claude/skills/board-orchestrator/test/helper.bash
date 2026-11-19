# shellcheck shell=bash
# Common setup for the board-orchestrator tests.

# shellcheck disable=SC2034 # Used by the test files.
SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

base_setup() {
  # On macOS, TMPDIR is under /var, a link to /private/var, and pwd -P in the scripts
  # gives /private/var. Use the real path, so that the paths in the log match.
  BATS_TEST_TMPDIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$HOME" "$FAKE_DIR"
  : >"$FAKE_LOG"
  unset OBSIDIAN_VAULT_PATH REX_BLOCK REX_SESSION REX_CLIENT BOARD_TERM BOARD BOARD_ROLE BOARD_NAME BOARD_ORCHESTRATOR
}

setup() { base_setup; }

# calls PATTERN: the logged calls that match PATTERN (grep -E).
calls() { grep -E -- "$1" "$FAKE_LOG" || true; }

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

# repo_with_push_policy DIR: a repo folder with an allow push policy.
repo_with_push_policy() {
  mkdir -p "$1/.claude"
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$1/.claude/settings.local.json"
}

# record_worker ADDR BOARD SESSION [REPORT]: a line in the workers record.
record_worker() {
  local dir="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$dir" "$BATS_TEST_TMPDIR/repo"
  printf '%s\ttask\t%s\t%s\t%s\t%s\tfix-login\n' "$1" "$2" "${4:-$dir/fix-login-1.md}" "$3" \
    "$BATS_TEST_TMPDIR/repo" >>"$dir/workers"
}

# rex_setup: the setup for the tests of the Rex backend. The caller is not in a pane.
rex_setup() {
  base_setup
  export REX_BIN="${FAKES:-$BATS_TEST_DIRNAME}/fake-rex"
  export BOARD_REX_POLL=0
  unset REX_BLOCK REX_SESSION REX_CLIENT BOARD BOARD_ROLE BOARD_NAME BOARD_ORCHESTRATOR FAKE_REX_FAIL FAKE_REX_SEND_FAIL FAKE_REX_KILL_FAIL FAKE_REX_KILL_HUP
  mkdir -p "$FAKE_DIR/rex"
}

# fake_block SESSION BLOCK WINDOW LABEL [claude|shell]: a live Rex block.
fake_block() {
  local fix="$SKILL_DIR/test/fixtures/rex"
  jq -cn --arg s "$1" --arg b "$2" --arg w "$3" --arg l "$4" \
    '{session_id:$s, window_id:$w, window_label:$l, block_id:$b}' >>"$FAKE_DIR/rex/blocks.jsonl"
  cp "$fix/process-${5:-claude}.json" "$FAKE_DIR/rex/process-$2.json"
}

# rex_status BLOCK working|blocked|idle [MSG]: the program status of a block.
rex_status() {
  jq -cn --arg s "$2" --arg m "${3:-}" \
    '{records: [{state:$s, app:"claude-code"} + (if $m != "" then {kind:"permission", msg:$m} else {} end)]}' \
    >"$FAKE_DIR/rex/status-$1.json"
}

# rex_record_file BLOCK JSON: the record of the block in the state folder.
rex_record_file() {
  local dir="$XDG_STATE_HOME/board-orchestrator-hc/rex"
  mkdir -p "$dir"
  printf '%s\n' "$2" >"$dir/$1.json"
}

# rex_orchestrator BLOCK BOARD: the caller is the orchestrator block BLOCK of BOARD.
rex_orchestrator() {
  fake_block session:fake-1 "$1" window:fake-1 orchestrator claude
  rex_record_file "$1" "$(jq -cn --arg b "$2" \
    '{board:$b, role:"orchestrator", rex_session:"session:fake-1", window:"window:fake-1"}')"
  export REX_BLOCK=$1 REX_SESSION=session:fake-1
}

# rex_worker BLOCK BOARD SESSION: a live worker block, with its record and workers line.
rex_worker() {
  fake_block session:fake-1 "$1" "window:w-${1: -4}" "worker-${1: -4}" claude
  rex_record_file "$1" "$(jq -cn --arg b "$2" --arg s "$3" --arg w "window:w-${1: -4}" \
    '{board:$b, role:"worker", session:$s, typed:"task", rex_session:"session:fake-1", window:$w, name:"worker"}')"
  record_worker "$1" "$2" "$3"
}
