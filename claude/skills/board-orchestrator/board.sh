#!/usr/bin/env bash
# The board orchestrator in herdr-app or in Renux. The herdr-app mods board-open and
# board-stop call this script, and so do the Renux popups.
#
#   board.sh boards        JSON [{key, board}] of the vault boards, by name
#   board.sh running [all] JSON [board] of the boards whose orchestrator runs in the
#                          backend of the caller (all: in both backends)
#   board.sh open BOARD    show the orchestrator of BOARD, start it when it does not run
#   board.sh stop BOARD    close the space (herdr-app) or the session (Renux) of the
#                          orchestrator of BOARD
#   board.sh restart BOARD ADDR
#                          start the orchestrator of BOARD again in the shell of its
#                          terminal ADDR, with no focus. claude-resume.sh runs it when a
#                          restart or a reboot put a new shell there. Exit 3 when ADDR is
#                          not the recorded orchestrator of BOARD.
#
# A board is a file Boards/*.md in the vault with the line "kanban-plugin: board". The
# orchestrator is a claude in the hc terminal of the space "BOARD orchestrator", with
# the labels board=BOARD and board.role=orchestrator. In Renux it is a claude in the
# session "BOARD orchestrator", and a record file of term.sh keeps the labels. The address
# of the record tells the backend. A board runs in one backend: open refuses it in the
# other. Its workers are its children (dispatch.sh start), so they end with it. Each start
# is a new claude session: rule 1 of the skill offers to resume the stopped workers.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

ORCHESTRATOR_AUTOCOMPACT=200k

fail() {
  printf 'board.sh: %s\n' "$1" >&2
  exit 1
}

# claude_command BOARD ADDR: the command line that the orchestrator shell ADDR runs. A Renux
# block has no labels in its env, so the line sets BOARD and BOARD_ROLE.
claude_command() {
  local args prefix=""
  printf -v args '%q' "/board-orchestrator $1"
  if [ "$(term_of "$2")" = rex ]; then
    printf -v prefix 'BOARD=%q BOARD_ROLE=orchestrator ' "$1"
  fi
  printf '%sclaude --effort high --autocompact %s -n %s-orchestrator -- %s\n' \
    "$prefix" "$ORCHESTRATOR_AUTOCOMPACT" "$(board_slug "$1")" "$args"
}

# cli_of ADDR: the name of the CLI of the backend of ADDR, for the error texts.
cli_of() { if [ "$(term_of "$1")" = rex ]; then printf 'rex\n'; else printf 'hc\n'; fi; }

# app_of ADDR: the name of the app of the backend of ADDR, for the error texts.
app_of() { if [ "$(term_of "$1")" = rex ]; then printf 'Renux\n'; else printf 'herdr-app\n'; fi; }

# space_text WHAT [ADDR]: the error text for a space (herdr-app) or a session (Renux).
# WHAT is open, none or close. The backend comes from ADDR, or from the caller.
space_text() {
  local backend
  backend=$(term_here)
  [ -z "${2:-}" ] || backend=$(term_of "$2")
  if [ "$backend" = rex ]; then
    case "$1" in
      open) printf 'Renux did not open the session\n' ;;
      none) printf 'Renux gave no terminal for the session\n' ;;
      close) printf 'Renux did not close the session\n' ;;
    esac
  else
    case "$1" in
      open) printf 'herdr-app did not open the space\n' ;;
      none) printf 'herdr-app gave no terminal for the space\n' ;;
      close) printf 'herdr-app did not close the space\n' ;;
    esac
  fi
}

# boards: the board names, one for each line, sorted.
boards() {
  local vault file
  vault=$(vault_path) || fail "no vault: set OBSIDIAN_VAULT_PATH"
  for file in "$vault"/Boards/*.md; do
    if [ -f "$file" ] && grep -qx 'kanban-plugin: board' "$file"; then
      basename "$file" .md
    fi
  done
}

# with_lock BOARD COMMAND...: run COMMAND while no other open or stop of BOARD runs. A
# lock folder, not flock: a Mac has no flock without Homebrew.
with_lock() {
  local lock tries=50
  lock="$(state_dir)/board-$(board_slug "$1").lock"
  shift
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries - 1))
    [ "$tries" -gt 0 ] || fail "another start or stop of this board runs ($lock)"
    sleep 0.1
  done
  # The path goes into the trap text: the local variable is gone when the trap runs.
  # shellcheck disable=SC2064
  trap "rmdir $(printf '%q' "$lock") 2>/dev/null || true" EXIT
  "$@"
}

# TYPED_SECONDS: for this time after a start command went into a shell, claude can still
# be starting there (a shell reads its .zshrc first). A second start command in that time
# would become the first prompt of the orchestrator.
TYPED_SECONDS=60

# start_in ADDR BOARD JSON: type the start command of the orchestrator of BOARD in the
# shell ADDR, whose hc get is JSON. Skip it when that shell got it less than
# TYPED_SECONDS ago: the label board.typed holds "PID EPOCH" of the last one.
start_in() {
  local addr=$1 board=$2 json=$3 pid typed now
  pid=$(jq -r '.pid // empty' <<<"$json")
  typed=$(jq -r '.labels["board.typed"] // empty' <<<"$json")
  now=$(date +%s)
  if [ -n "$pid" ] && [ "${typed%% *}" = "$pid" ] && [[ "${typed#* }" =~ ^[0-9]+$ ]] &&
    [ $((now - ${typed#* })) -lt "$TYPED_SECONDS" ]; then
    return 0
  fi
  term_label "$addr" "board.typed=$pid $now" || fail "$(cli_of "$addr") did not label $addr"
  term_send "$addr" "$(claude_command "$board" "$addr")" || fail "$(cli_of "$addr") did not start claude in $addr"
}

# watch_board ADDR: in Renux, make sure that the board watcher listens to the session of ADDR.
# Rex does not tell an orchestrator about its workers. A failed start does not stop the board.
watch_board() {
  [ "$(term_of "$1")" = rex ] || return 0
  rex_watch "$(rex_session_of "$1")" || true
}

open_board() {
  local board=$1 addr json vault
  addr=$(orchestrator_of "$board") || addr=""
  if [ -n "$addr" ]; then
    # A live orchestrator in the other backend: stop it there first.
    if [ "$(term_of "$addr")" != "$(term_here)" ]; then
      if [ "$(term_of "$addr")" = hc ]; then
        fail "$board runs in herdr-app. Stop it there first."
      else
        fail "$board runs in Renux. Stop it there first."
      fi
    fi
    json=$(term_get "$addr") || json="{}"
    if [ "$(jq -r '.foreground.name // empty' <<<"$json")" = claude ]; then
      term_focus_agent "$addr" || fail "$(app_of "$addr") did not show $addr"
      watch_board "$addr"
      return 0
    fi
    # After a reboot the terminal is a shell in the same place, with no agent status:
    # show its pane, then start claude in it.
    term_focus_pane "$addr" || fail "$(app_of "$addr") did not show $addr"
    watch_board "$addr"
    start_in "$addr" "$board" "$json"
    return 0
  fi
  vault=$(vault_path) || fail "no vault: set OBSIDIAN_VAULT_PATH"
  # The space first: the key shows a result at once. Claude starts after that.
  addr=$(term_space_new "$board" "$vault") || fail "$(space_text open)"
  [ -n "$addr" ] || fail "$(space_text none)"
  term_label "$addr" "board=$board" board.role=orchestrator || fail "$(cli_of "$addr") did not label $addr"
  printf '%s\t%s\n' "$addr" "$board" >"$(record_file "$board")"
  watch_board "$addr"
  term_send "$addr" "$(claude_command "$board" "$addr")" || fail "$(cli_of "$addr") did not start claude in $addr"
}

# restart_board BOARD ADDR: start claude in the shell ADDR of the orchestrator of BOARD.
restart_board() {
  local board=$1 addr=$2 json
  # Only the recorded orchestrator: a stale terminal of the board must not start a second one.
  if [ "$(orchestrator_of "$board" 2>/dev/null)" != "$addr" ]; then
    printf 'board.sh: %s is not the orchestrator of the board %s\n' "$addr" "$board" >&2
    exit 3
  fi
  json=$(term_get "$addr") || fail "$(cli_of "$addr") did not show $addr"
  watch_board "$addr"
  [ "$(jq -r '.foreground.name // empty' <<<"$json")" != claude ] || return 0
  start_in "$addr" "$board" "$json"
}

stop_board() {
  local board=$1 addr rc=0 record=""
  addr=$(orchestrator_of "$board") || fail "no orchestrator of the board $board runs"
  # ctrl+b X in Renux can run in the session that the stop kills: the kill ends this script
  # with SIGHUP. So the records go first (rex_space_close deletes the block record), and
  # come back when the kill fails. With no record, the next open would start a second
  # orchestrator.
  if [ "$(term_of "$addr")" = rex ]; then
    record=$(cat "$(record_file "$board")")
    rm -f "$(record_file "$board")"
  fi
  # term_space_close: exit 2 when the terminal has no space of its own.
  term_space_close "$addr" || rc=$?
  case "$rc" in
    0) ;;
    2) term_kill "$addr" || true ;;
    *)
      [ -z "$record" ] || printf '%s\n' "$record" >"$(record_file "$board")"
      fail "$(space_text close "$addr")"
      ;;
  esac
  # A Renux block record has no use now. An hc terminal has no record file of ours.
  [ "$(term_of "$addr")" != rex ] || term_rm "$addr" || true
  # The worker records stay: the next orchestrator offers to resume them.
  rm -f "$(record_file "$board")"
}

case "${1:-}" in
  boards)
    boards | jq -Rn '[inputs] | to_entries | map({key: (.key + 1 | tostring), board: .value})'
    ;;
  running)
    # Only the boards of the backend of the caller: a stop popup stops the only board at
    # once, so it must not stop a board of the other app. The herdr-app mods run with no
    # env, so they get hc.
    here=$(term_here)
    for f in "$(state_dir)"/orchestrator-*; do
      [ -f "$f" ] || continue
      [ "${2:-}" = all ] || [ "$(term_of "$(cut -f1 "$f")")" = "$here" ] || continue
      board=$(cut -f2 "$f")
      ! orchestrator_of "$board" >/dev/null || printf '%s\n' "$board"
    done | jq -Rn '[inputs]'
    ;;
  restart)
    board="${2:-}" addr="${3:-}"
    [ -n "$board" ] && [ -n "$addr" ] || { printf 'usage: board.sh restart BOARD ADDRESS\n' >&2; exit 2; }
    with_lock "$board" restart_board "$board" "$addr"
    ;;
  open | stop)
    board="${2:-}"
    [ -n "$board" ] || { printf 'usage: board.sh %s BOARD\n' "$1" >&2; exit 2; }
    # stop pings the backend of the record, open the backend of the caller.
    if [ "$1" = stop ] && [ -f "$(record_file "$board")" ]; then
      err=$(term_ping_of "$(cut -f1 "$(record_file "$board")")" 2>&1) || fail "${err%%$'\n'*}"
    else
      err=$(term_ping 2>&1) || fail "${err%%$'\n'*}"
    fi
    if [ "$1" = open ]; then
      # No grep -q in a pipe: it stops early, boards gets SIGPIPE, and pipefail fails.
      grep -qxF -- "$board" <<<"$(boards)" || fail "no board $board in the vault"
      with_lock "$board" open_board "$board"
    else
      with_lock "$board" stop_board "$board"
    fi
    ;;
  *)
    printf 'usage: board.sh boards|running [all]|open BOARD|stop BOARD|restart BOARD ADDRESS\n' >&2
    exit 2
    ;;
esac
