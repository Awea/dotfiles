#!/usr/bin/env bash
# Resume Claude in the hc terminals that lost it at a restart. The claude-resume mod runs
# tick every 30 seconds while herdr-app is open.
#
#   claude-resume.sh record   label each terminal that runs Claude with its session
#   claude-resume.sh resume   type claude --resume in each terminal that lost Claude
#   claude-resume.sh tick     resume, then record
#
# A tick resumes again and again: after a boot, a shell can still read its .zshrc at the
# first tick, and a restart of the core kills Claude while the window stays open.
#
# record reads the file Claude Code keeps for the claude process in the foreground,
# ~/.claude/sessions/<pid>.json, and writes these labels on the terminal:
#
#   claude.session  the session ID
#   claude.cwd      the folder of the session (claude --resume finds the session there)
#   claude.pid      the pid of the program of the terminal (the shell, or Claude itself)
#   claude.start    the start time of that program (a pid can come back after a reboot)
#
# The same session keeps the claude.cwd of its first record: after a cd, the file can
# give another folder. An idle shell in the same process means an exit: record removes
# the labels.
#
# A restart kills Claude, and hc gives a kept terminal a new shell: a new pid, or the
# same pid with a new start time after a reboot. In each live terminal with a new shell
# that is idle (its own program in the foreground), resume types:
#
#   cd '<claude.cwd>' && claude --resume <claude.session>
#
# A board orchestrator gets its labels too. In its new shell, resume runs board.sh restart:
# a new orchestrator session, that starts at rule 1 and offers to resume the workers of
# the board. board.sh holds the lock of the board, so alt-shift-b types no second start. resume and record skip the other board terminals (the
# workers): the orchestrator resumes them.
# Both exit 1 when hc ls, a label or a send fails.
set -uo pipefail
HC=("${HC_BIN:-hc}")
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

UUID='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
SEP=$'\x1f'
SESSIONS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
BOARD_SH="$HOME/.claude/skills/board-orchestrator/board.sh"

usage() {
  printf 'usage: claude-resume.sh record|resume|tick\n' >&2
  exit 2
}

# quote TEXT: TEXT as one shell word in single quotes. The replacement is in a variable:
# bash 4.2 and older (macOS /bin/bash) keep the backslashes of a literal one.
quote() {
  local q="'\\''"
  printf "'%s'" "${1//\'/$q}"
}

# started PID: the start time of PID, empty when ps cannot tell.
started() {
  ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'
}

# same_start A B: exit 0 when the start times A and B do not show another process. An
# empty one tells nothing.
same_start() {
  [ -z "$1" ] || [ -z "$2" ] || [ "$1" = "$2" ]
}

# label ADDR K=V...: set the labels of ADDR.
label() {
  "${HC[@]}" label "$@" >/dev/null
}

# record ADDR: the labels of the Claude session in the foreground of ADDR, or no labels
# after an exit.
record() {
  local addr=$1 session cwd start
  # The name too: Claude keeps the file after a crash, and its pid can come back.
  if [ "${fg_name##*/}" = claude ] && [ -f "$SESSIONS/$fg_pid.json" ]; then
    IFS=$SEP read -r session cwd < <(jq -r --arg sep "$SEP" \
      '[.sessionId // "", .cwd // ""] | join($sep)' "$SESSIONS/$fg_pid.json") || return 0
    [[ "$session" =~ $UUID ]] || return 0
    [ "$session" != "$l_session" ] || [ -z "$l_cwd" ] || cwd=$l_cwd
    start=$(started "$pid")
    [ "$session $cwd $pid $start" != "$l_session $l_cwd $l_pid $l_start" ] || return 0
    label "$addr" "claude.session=$session" "claude.cwd=$cwd" "claude.pid=$pid" "claude.start=$start"
  elif [ -n "$l_session" ] && [ "$fg_pid" = "$pid" ] && [ "$l_pid" = "$pid" ] &&
    same_start "$(started "$pid")" "$l_start"; then
    label "$addr" claude.session= claude.cwd= claude.pid= claude.start=
  fi
}

# resume ADDR: claude --resume in ADDR when a new shell, idle, replaced Claude. In a board
# orchestrator: board.sh restart.
resume() {
  local addr=$1 start err rc
  [ -n "$l_pid" ] && [ "$fg_pid" = "$pid" ] || return 0
  [[ "$l_session" =~ $UUID ]] || return 0
  start=$(started "$pid")
  # The same shell as when Claude started: Claude ended in it, or still runs.
  if [ "$pid" = "$l_pid" ] && same_start "$start" "$l_start"; then return 0; fi
  # The new shell first: a second run before Claude starts finds nothing to do.
  label "$addr" "claude.pid=$pid" "claude.start=$start" || return 1
  if [ -n "$board" ]; then
    err=$(bash "$BOARD_SH" restart "$board" "$addr" 2>&1 >/dev/null) && rc=0 || rc=$?
    [ "$rc" -ne 0 ] || { printf 'claude-resume: %s: orchestrator of %s\n' "$addr" "$board"; return 0; }
    printf 'claude-resume: %s: %s\n' "$addr" "${err:-board.sh restart failed}" >&2
    # Exit 3: not the orchestrator of its board. The new labels stay: no try at each tick.
    [ "$rc" -eq 3 ] || label "$addr" "claude.pid=$l_pid" "claude.start=$l_start" || true
    return 1
  fi
  if ! "${HC[@]}" send "$addr" "cd $(quote "${l_cwd:-.}") && claude --resume $l_session" >/dev/null; then
    printf 'claude-resume: %s: hc send failed\n' "$addr" >&2
    label "$addr" "claude.pid=$l_pid" "claude.start=$l_start" || true
    return 1
  fi
  printf 'claude-resume: %s: %s\n' "$addr" "$l_session"
}

cmd=${1:-}
case "$cmd" in record | resume | tick) ;; *) usage ;; esac

if ! list=$("${HC[@]}" ls --json 2>&1); then
  printf 'claude-resume: hc ls failed: %s\n' "$list" >&2
  exit 1
fi

failed=0
for addr in $(jq -r '.terminals[] | select(.state == "live") | .address' <<<"$list"); do
  term=$("${HC[@]}" get "$addr" 2>/dev/null) || continue
  # One field for each value, joined with the unit separator: read merges empty fields
  # between tabs.
  fields=$(jq -r --arg sep "$SEP" '
    select(.state == "live" and ((.labels.board // "") == "" or .labels["board.role"] == "orchestrator"))
    | [(.pid // "" | tostring), (.foreground.pid // "" | tostring), .foreground.name // "",
       (.labels | .["claude.session"], .["claude.cwd"], .["claude.pid"], .["claude.start"],
         (if .["board.role"] == "orchestrator" then .board else "" end) | . // "")] | join($sep)' <<<"$term")
  [ -n "$fields" ] || continue
  IFS=$SEP read -r pid fg_pid fg_name l_session l_cwd l_pid l_start board <<<"$fields"
  [ -n "$pid" ] || continue
  case "$cmd" in
    record) record "$addr" || failed=1 ;;
    resume) resume "$addr" || failed=1 ;;
    tick)
      # Just after a send the shell is still idle. record uses the labels read before
      # the send (the old pid), so it sees no exit there.
      resume "$addr" || failed=1
      record "$addr" || failed=1
      ;;
  esac
done
exit "$failed"
