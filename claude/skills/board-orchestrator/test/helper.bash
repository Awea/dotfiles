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

# prompt_file SESSION TEXT: the first prompt of the worker SESSION, kept by start. Prints
# the path of the file.
prompt_file() {
  local dir="$XDG_STATE_HOME/board-orchestrator-hc/prompts"
  mkdir -p "$dir"
  printf '%s\n' "$2" >"$dir/$1.md"
  printf '%s\n' "$dir/$1.md"
}

# rex_setup: the setup for the tests of the Rex backend. The caller is not in a pane.
rex_setup() {
  base_setup
  export REX_BIN="${FAKES:-$BATS_TEST_DIRNAME}/fake-rex"
  export BOARD_REX_POLL=0
  unset REX_BLOCK REX_SESSION REX_CLIENT BOARD BOARD_ROLE BOARD_NAME BOARD_ORCHESTRATOR FAKE_REX_FAIL FAKE_REX_SEND_FAIL FAKE_REX_KILL_FAIL FAKE_REX_KILL_HUP FAKE_REX_KEY_FAIL
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

# queue_watcher SESSION [OUTBOX]: a live board watcher of SESSION. With OUTBOX it is a
# watcher that delivers the queue, without it an old watcher. Its pid goes to the pid
# file of the session and to watchers.pids, for kill_watchers.
queue_watcher() {
  local dir="$XDG_STATE_HOME/board-orchestrator-hc/rex" out=""
  mkdir -p "$dir"
  [ -z "${2:-}" ] || out=" outbox=$2"
  bash -c 'exec -a "rex do -s $0 /x/board-watch.lua dispatch=/x/dispatch.sh session=$0$1" sleep 30' \
    "$1" "$out" &
  printf '%s\n' "$!" >"$dir/watch-$1.pid"
  printf '%s\n' "$!" >>"$BATS_TEST_TMPDIR/watchers.pids"
}

# kill_watchers: stop the processes of queue_watcher.
kill_watchers() {
  [ -f "$BATS_TEST_TMPDIR/watchers.pids" ] || return 0
  xargs kill <"$BATS_TEST_TMPDIR/watchers.pids" 2>/dev/null || true
}

# screen LINE...: the VT screen of a Claude Code block, in capture.txt. The LINEs make the
# input box, between two rule lines. The top one has a label. Above it is an old prompt
# of the user.
screen() {
  local rule=$'\e[0m\e[38;2;136;136;136m────────────────────────────────\e[0m' l
  {
    printf '%s\r\n' $'\e[0m\e[48;2;55;55;55m❯\xc2\xa0old prompt\e[0m' '' 'an answer' ''
    # Claude Code can put a label at the end of the top rule.
    printf '%s\r\n' "${rule%$'\e[0m'} my-session ─"$'\e[0m'
    for l in "$@"; do printf '%s\r\n' "$l"; done
    printf '%s\r\n' "$rule" $'\e[2C\e[0m\e[38;2;153;153;153mctx 91k/1M\e[0m'
  } >"$FAKE_DIR/rex/capture.txt"
}

# The input-box lines for screen. PROMPT is the gray prompt sign and a no-break space.
PROMPT=$'\e[0m\e[38;2;153;153;153m❯\xc2\xa0\e[0m'

# fake_spawners: setsid and nohup that log their arguments and start nothing. lib.sh puts
# $HOME/.local/bin first in PATH, so they go there.
fake_spawners() {
  mkdir -p "$HOME/.local/bin"
  for p in setsid nohup; do
    printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >>"$FAKE_DIR/spawn.log"\n' "$p" >"$HOME/.local/bin/$p"
    chmod +x "$HOME/.local/bin/$p"
  done
}
