#!/usr/bin/env bash
# The board orchestrator in herdr-app. The herdr-app mods board-open and board-stop call
# this script.
#
#   board.sh boards        JSON [{key, board}] of the vault boards, by name
#   board.sh running       JSON [board] of the boards whose orchestrator runs
#   board.sh open BOARD    show the orchestrator of BOARD, start it when it does not run
#   board.sh stop BOARD    close the space of the orchestrator of BOARD
#
# A board is a file Boards/*.md in the vault with the line "kanban-plugin: board". The
# orchestrator is a claude in the hc terminal of the space "BOARD orchestrator", with
# the labels board=BOARD and board.role=orchestrator. Its workers are its hc children
# (dispatch.sh start), so they end with it. Each start is a new claude session: rule 1
# of the skill offers to resume the stopped workers.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

ORCHESTRATOR_AUTOCOMPACT=200k

fail() {
  printf 'board.sh: %s\n' "$1" >&2
  exit 1
}

# record_file BOARD: "ADDRESS<tab>BOARD" of the orchestrator of BOARD.
record_file() { printf '%s/orchestrator-%s\n' "$(state_dir)" "$(board_slug "$1")"; }

# orchestrator_of BOARD: the address of the live orchestrator of BOARD, or exit 1.
orchestrator_of() {
  local f addr
  f=$(record_file "$1")
  [ -f "$f" ] || return 1
  addr=$(cut -f1 "$f")
  [ -n "$addr" ] && has_labels "$addr" "$1" orchestrator || return 1
  printf '%s\n' "$addr"
}

# claude_command BOARD: the command line that the orchestrator shell runs.
claude_command() {
  local args
  printf -v args '%q' "/board-orchestrator $1"
  printf 'claude --effort high --autocompact %s -n %s-orchestrator -- %s\n' \
    "$ORCHESTRATOR_AUTOCOMPACT" "$(board_slug "$1")" "$args"
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

open_board() {
  local board=$1 addr fg vault out
  addr=$(orchestrator_of "$board") || addr=""
  if [ -n "$addr" ]; then
    fg=$("${HC[@]}" get "$addr" --json 2>/dev/null | jq -r '.foreground.name // empty') || fg=""
    if [ "$fg" = claude ]; then
      "${HAPP[@]}" "do" agent.focus --terminal "$addr" >/dev/null || fail "herdr-app did not show $addr"
      return 0
    fi
    # After a reboot the terminal is a shell in the same place, with no agent status:
    # show its pane, then start claude in it.
    "${HAPP[@]}" "do" pane.focus --terminal "$addr" >/dev/null || fail "herdr-app did not show $addr"
    "${HC[@]}" send "$addr" "$(claude_command "$board")" >/dev/null || fail "hc did not start claude in $addr"
    return 0
  fi
  vault=$(vault_path) || fail "no vault: set OBSIDIAN_VAULT_PATH"
  # The space first: the key shows a result at once. Claude starts after that.
  out=$("${HAPP[@]}" "do" space.new --name "$board orchestrator" --folder "$vault" --tab orchestrator) ||
    fail "herdr-app did not open the space"
  addr=$(jq -r '.terminal // empty' <<<"$out")
  [ -n "$addr" ] || fail "herdr-app gave no terminal for the space"
  "${HC[@]}" label "$addr" "board=$board" board.role=orchestrator >/dev/null || fail "hc did not label $addr"
  printf '%s\t%s\n' "$addr" "$board" >"$(record_file "$board")"
  "${HC[@]}" send "$addr" "$(claude_command "$board")" >/dev/null || fail "hc did not start claude in $addr"
}

stop_board() {
  local board=$1 addr space
  addr=$(orchestrator_of "$board") || fail "no orchestrator of the board $board runs"
  space=$(hc_labels "$addr" | jq -r '.["herdr.space"] // empty')
  if [ -n "$space" ]; then
    "${HAPP[@]}" "do" space.close --id "$space" --confirmed true >/dev/null || fail "herdr-app did not close the space"
  else
    "${HC[@]}" kill "$addr" >/dev/null 2>&1 || true
  fi
  # The worker records stay: the next orchestrator offers to resume them.
  rm -f "$(record_file "$board")"
}

case "${1:-}" in
  boards)
    boards | jq -Rn '[inputs] | to_entries | map({key: (.key + 1 | tostring), board: .value})'
    ;;
  running)
    for f in "$(state_dir)"/orchestrator-*; do
      [ -f "$f" ] || continue
      board=$(cut -f2 "$f")
      ! orchestrator_of "$board" >/dev/null || printf '%s\n' "$board"
    done | jq -Rn '[inputs]'
    ;;
  open | stop)
    board="${2:-}"
    [ -n "$board" ] || { printf 'usage: board.sh %s BOARD\n' "$1" >&2; exit 2; }
    err=$("${HC[@]}" ls --json 2>&1 >/dev/null) || fail "hc does not answer: ${err%%$'\n'*}"
    if [ "$1" = open ]; then
      # No grep -q in a pipe: it stops early, boards gets SIGPIPE, and pipefail fails.
      grep -qxF -- "$board" <<<"$(boards)" || fail "no board $board in the vault"
      with_lock "$board" open_board "$board"
    else
      with_lock "$board" stop_board "$board"
    fi
    ;;
  *)
    printf 'usage: board.sh boards|running|open BOARD|stop BOARD\n' >&2
    exit 2
    ;;
esac
