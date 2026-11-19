#!/usr/bin/env bash
# Resume Claude in the Rex panes that lost it at a server restart. A Rex restart keeps the
# sessions, the panes and their block IDs, but each pane gets a new shell.
#
#   claude-resume.sh record   record the Claude session of each pane that runs Claude
#   claude-resume.sh resume   type claude --resume in each pane that lost Claude
#   claude-resume.sh tick     resume, then record
#   claude-resume.sh loop     tick every 30 seconds while the Rex server runs
#
# init.lua starts the loop at each config load. rex config check runs init.lua too: a loop
# whose parent is not the server exits at once. A pid file keeps one loop. The loop ends
# when the server does not answer. Each rex call has --autostart=false: the loop never
# starts a server.
#
# record reads the file Claude Code keeps for the claude process in the foreground,
# ~/.claude/sessions/<pid>.json, and keeps for each pane (block ID), in
# ~/.local/state/rex/claude-resume.json:
#
#   claude  the Claude session ID
#   cwd     the folder of the session (claude --resume finds the session there)
#   pid     the pid of the shell of the pane
#   start   the start time of that shell (a pid can come back after a reboot)
#
# The same session keeps the cwd of its first record: after a cd, the file can give
# another folder. An idle shell with the same pid means an exit: record removes the pane.
# A pane with a new shell that is idle (no program in the foreground) gets:
#
#   cd '<cwd>' && claude --resume <claude>
#
# A board pane has a record in ~/.local/state/board-orchestrator-hc/rex/<block>.json (see
# board.sh). The orchestrator of a board keeps only {board, pid, start} in the state: it has
# no claude field. In its new idle shell, resume runs board.sh restart BOARD BLOCK: a new
# orchestrator session, that offers to resume the workers of the board. Exit 3 means that
# the block is not the recorded orchestrator: resume prints the error and does not try again
# for this shell. Another failure keeps the old pid: resume tries again at the next tick.
# record and resume skip a worker block, and a board block with an unknown role: the new
# orchestrator closes the windows of the workers that a restart lost.
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

UUID='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
SESSIONS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rex"
STATE="$STATE_DIR/claude-resume.json"
BOARD_SH="${BOARD_SH:-$HOME/.claude/skills/board-orchestrator/board.sh}"
BOARDS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/board-orchestrator-hc/rex"
REX=("${REX_BIN:-rex}" --autostart=false)

# api METHOD JSON: call the Rex API.
api() { "${REX[@]}" api call "$1" "$2" 2>/dev/null; }

# started PID: the start time of PID, empty when ps cannot tell.
started() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }

# same_start A B: exit 0 when the start times A and B do not show another process. An
# empty one tells nothing.
same_start() { [ -z "$1" ] || [ -z "$2" ] || [ "$1" = "$2" ]; }

# quote TEXT: TEXT as one shell word in single quotes.
quote() {
  local q="'\\''"
  printf "'%s'" "${1//\'/$q}"
}

# put BLOCK JSON: set the record of BLOCK, or remove it when JSON is null.
put() {
  state=$(jq -c --arg b "$1" --argjson v "$2" 'if $v == null then del(.[$b]) else .[$b] = $v end' <<<"$state")
}

# record BLOCK: the record of the Claude session in the foreground of BLOCK, or no record
# after an exit. For a board orchestrator: {board, pid, start} while Claude runs in front.
record() {
  local block=$1 claude cwd start
  if [ -n "$board" ]; then
    [ "${fg_path##*/}" = claude ] || return 0
    start=$(started "$pid")
    [ "$board $pid $start" != "$(jq -r '[.board // "", .pid // "", .start // ""] | join(" ")' <<<"$entry")" ] || return 0
    put "$block" "$(jq -cn --arg b "$board" --arg p "$pid" --arg s "$start" '{board: $b, pid: $p, start: $s}')"
  elif [ "${fg_path##*/}" = claude ] && [ -f "$SESSIONS/$fg_pid.json" ]; then
    claude=$(jq -r '.sessionId // ""' "$SESSIONS/$fg_pid.json")
    cwd=$(jq -r '.cwd // ""' "$SESSIONS/$fg_pid.json")
    [[ "$claude" =~ $UUID ]] || return 0
    [ "$claude" != "$l_claude" ] || [ -z "$l_cwd" ] || cwd=$l_cwd
    start=$(started "$pid")
    [ "$claude $cwd $pid $start" != "$l_claude $l_cwd $l_pid $l_start" ] || return 0
    put "$block" "$(jq -cn --arg c "$claude" --arg d "$cwd" --arg p "$pid" --arg s "$start" \
      '{claude: $c, cwd: $d, pid: $p, start: $s}')"
  elif [ -n "$l_claude" ] && [ "$fg_pid" = "$pid" ] && [ "$l_pid" = "$pid" ] &&
    same_start "$(started "$pid")" "$l_start"; then
    put "$block" null
  fi
}

# resume SESSION BLOCK: claude --resume in BLOCK when a new shell, idle, replaced Claude.
resume() {
  local session=$1 block=$2 start err rc
  [ -n "$l_pid" ] && [ "$fg_pid" = "$pid" ] || return 0
  [ -n "$board" ] || [[ "$l_claude" =~ $UUID ]] || return 0
  start=$(started "$pid")
  # The same shell as when Claude started: Claude ended in it, or still runs.
  if [ "$pid" = "$l_pid" ] && same_start "$start" "$l_start"; then return 0; fi
  # The new shell first: a second run before Claude starts finds nothing to do.
  put "$block" "$(jq -c --arg p "$pid" --arg s "$start" '.pid = $p | .start = $s' <<<"$entry")"
  if [ -n "$board" ]; then
    err=$(bash "$BOARD_SH" restart "$board" "$block" 2>&1 >/dev/null) && rc=0 || rc=$?
    [ "$rc" -ne 0 ] || { printf 'claude-resume: %s: orchestrator of %s\n' "$block" "$board"; return 0; }
    printf 'claude-resume: %s: %s\n' "$block" "${err:-board.sh restart failed}" >&2
    # Exit 3: not the recorded orchestrator. The new pid stays: no try at each tick.
    [ "$rc" -eq 3 ] || put "$block" "$entry"
    return 1
  fi
  if ! "${REX[@]}" send -s "$session" -b "$block" \
    "cd $(quote "${l_cwd:-.}") && claude --resume $l_claude" >/dev/null ||
    ! "${REX[@]}" send-key -s "$session" -b "$block" enter >/dev/null; then
    printf 'claude-resume: %s: rex send failed\n' "$block" >&2
    put "$block" "$entry"
    return 1
  fi
  printf 'claude-resume: %s: %s\n' "$block" "$l_claude"
}

# run CMD: record, resume or tick over every terminal pane of every session.
run() {
  local cmd=$1 failed=0 sessions session blocks block info seen='[]'
  mkdir -p "$STATE_DIR"
  state=$(cat "$STATE" 2>/dev/null) || state='{}'
  jq -e 'type == "object"' <<<"$state" >/dev/null 2>&1 || state='{}'
  sessions=$(api session.list '{}') || { echo 'claude-resume: rex does not answer' >&2; return 1; }
  for session in $(jq -r '.sessions[].session_id' <<<"$sessions"); do
    blocks=$(api session.list_blocks "$(jq -cn --arg s "$session" '{session_id: $s}')") || continue
    for block in $(jq -r '.blocks[] | select(.creator_name == "com.superlogical.terminal") | .block_id' <<<"$blocks"); do
      seen=$(jq -c --arg b "$block" '. + [$b]' <<<"$seen")
      info=$(api block.method "$(jq -cn --arg s "$session" --arg b "$block" \
        '{session_id: $s, block_id: $b, method: "process"}')") || continue
      pid=$(jq -r '.child.pid // "" | tostring' <<<"$info")
      fg_pid=$(jq -r '.foreground.pid // "" | tostring' <<<"$info")
      fg_path=$(jq -r '.foreground.invoked_path // .foreground.path // ""' <<<"$info")
      [ -n "$pid" ] || continue
      entry=$(jq -c --arg b "$block" '.[$b] // {}' <<<"$state")
      # A board block: the orchestrator only. A worker, or an unknown role, is skipped.
      board=""
      if [ -f "$BOARDS_DIR/$block.json" ]; then
        board=$(jq -r 'select(.role == "orchestrator") | .board // empty' "$BOARDS_DIR/$block.json" 2>/dev/null)
        [ -n "$board" ] || continue
      fi
      l_claude=$(jq -r '.claude // ""' <<<"$entry")
      l_cwd=$(jq -r '.cwd // ""' <<<"$entry")
      l_pid=$(jq -r '.pid // ""' <<<"$entry")
      l_start=$(jq -r '.start // ""' <<<"$entry")
      case "$cmd" in
        record) record "$block" || failed=1 ;;
        resume) resume "$session" "$block" || failed=1 ;;
        tick)
          # Just after a send the shell is still idle. record uses the record read
          # before the send (the old pid), so it sees no exit there.
          resume "$session" "$block" || failed=1
          record "$block" || failed=1
          ;;
      esac
    done
  done
  # A pane that is gone loses its record.
  state=$(jq -c --argjson seen "$seen" 'with_entries(select(.key as $k | $seen | index($k)))' <<<"$state")
  printf '%s\n' "$state" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  return "$failed"
}

# loop: tick every 30 seconds. One loop: a second one exits at once.
loop() {
  local pidfile="$STATE_DIR/claude-resume.pid" other server
  server=$("${REX[@]}" server status 2>/dev/null | awk '$1 == "pid:" { print $2 }')
  [ "${REX_RESUME_ANY_PARENT:-}" = 1 ] || [ "$PPID" = "$server" ] || exit 0
  mkdir -p "$STATE_DIR"
  other=$(cat "$pidfile" 2>/dev/null)
  if [ -n "$other" ] && [ "$other" != $$ ] && kill -0 "$other" 2>/dev/null &&
    ps -o args= -p "$other" | grep -q 'claude-resume.sh loop'; then
    exit 0
  fi
  echo $$ >"$pidfile"
  while "${REX[@]}" server status >/dev/null 2>&1; do
    run tick
    sleep "${REX_RESUME_EVERY:-30}"
  done
}

case "${1:-}" in
  record | resume | tick) run "$1" ;;
  loop) loop ;;
  *) echo 'usage: claude-resume.sh record|resume|tick|loop' >&2; exit 2 ;;
esac
