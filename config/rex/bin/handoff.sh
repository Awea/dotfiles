#!/usr/bin/env bash
# ctrl+b shift+a in Renux: run /handoff in the focused claude, then continue in a new tab.
# The Rex config runs the popup in a floating pane. The popup asks a focus, an effort and
# the tab focus, starts the worker detached, and ends at once.
#
#   handoff.sh DIR SESSION BLOCK CLIENT   the popup
#   handoff.sh run DIR SESSION BLOCK FOCUS EFFORT focus|background
#                                         the worker: logs to ~/.local/state/rex/handoff.log
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# block_info SESSION BLOCK METHOD: the JSON of a terminal method, such as program_status.
block_info() {
  rex api call block.method "$(jq -cn --arg s "$1" --arg b "$2" --arg m "$3" \
    '{session_id: $s, block_id: $b, method: $m}')" 2>/dev/null || echo '{}'
}

# state SESSION BLOCK: the claude state of BLOCK (idle, working, done, blocked, error), or
# empty when BLOCK runs no claude.
state() {
  block_info "$1" "$2" program_status |
    jq -r '[.records[]? | select(.app == "claude-code")][0].state // empty'
}

# fail SESSION DIR ERROR: a tab that shows the error and the log path.
fail() {
  printf '%s\n' "$3" >&2
  rex window new -s "$1" --cwd "$2" "handoff failed" -- \
    sh -c 'printf "%s\n" "$0" "Log: $1"; exec "${SHELL:-sh}"' "$3" "$log" >/dev/null || true
  exit 1
}

log="${XDG_STATE_HOME:-$HOME/.local/state}/rex/handoff.log"

run() {
  local dir=$1 session=$2 block=$3 focus=$4 effort=$5 tabfocus=$6 doc title st deadline
  doc="${TMPDIR:-/tmp}/rex-handoff-$(date +%Y%m%d-%H%M%S)-$$.md"
  # The title of the new session: the focus, else the source title with "handoff".
  # Without it, claude makes a title from the first prompt, the same for each handoff.
  title=$focus
  if [[ -z $title ]]; then
    title=$(block_info "$session" "$block" title | jq -r '.title // empty')
    case $title in "" | claude | "Claude Code") title= ;; *) title="$title handoff" ;; esac
  fi
  rex send -s "$session" -b "$block" "/handoff ${focus:+$focus. }Save the handoff document to $doc"
  sleep 0.3
  rex send-key -s "$session" -b "$block" enter
  # Wait for the turn to start, then for idle or done. A turn can stop at a permission
  # prompt (blocked): wait on, up to 15 minutes.
  deadline=$((SECONDS + ${REX_HANDOFF_WAIT:-900}))
  for _ in $(seq 20); do
    [[ $(state "$session" "$block") == idle ]] || break
    sleep 0.5
  done
  while :; do
    st=$(state "$session" "$block")
    [[ -z $st || $st == idle || $st == done ]] && break
    ((SECONDS < deadline)) || fail "$session" "$dir" "The handoff did not end in 15 minutes."
    sleep 2
  done
  [[ -s $doc ]] || fail "$session" "$dir" "The agent did not write $doc."
  local argv=(claude)
  [[ -z $title ]] || argv+=(-n "$title")
  [[ -z $effort ]] || argv+=(--effort "$effort")
  argv+=("Read the handoff document at $doc, then continue the work.")
  local on=true
  [[ $tabfocus == focus ]] || on=false
  rex window new -s "$session" --cwd "$dir" --focus="$on" -- "${argv[@]}" >/dev/null
}

# key: one key press. Escape closes the popup.
key() {
  local k
  IFS= read -rsn1 k
  [[ $k == $'\e' ]] && exit 0
  printf '%s' "$k"
}

popup() {
  local dir=$1 session=$2 block=$3 st focus effort= tabfocus=background
  printf '\e[1mHandoff to a new claude tab\e[0m   (ctrl+c closes)\n\n'
  st=$(state "$session" "$block")
  if [[ $st != idle && $st != done ]]; then
    printf 'Focus an idle claude agent, then try again (state: %s).\nPress a key to close.' "${st:-no claude}"
    key >/dev/null
    exit 0
  fi
  read -r -e -p 'Focus for the next session (Enter to skip): ' focus
  printf 'Effort [l]ow [m]edium [h]igh [x]high [M]ax (Enter for default) '
  while :; do
    case $(key) in
      l) effort=low ;; m) effort=medium ;; h) effort=high ;; x) effort=xhigh ;; M) effort=max ;;
      "") ;;
      *) continue ;;
    esac
    break
  done
  printf '%s\n' "${effort:-default}"
  printf 'Focus the new tab? [y/N] '
  while :; do
    case $(key) in
      y) tabfocus=focus ;;
      n | "") ;;
      *) continue ;;
    esac
    break
  done
  printf '%s\n' "$tabfocus"
  # Detached from the popup pane, which closes now. No setsid on macOS.
  mkdir -p "${log%/*}"
  if command -v setsid >/dev/null; then
    setsid -f bash "$0" run "$dir" "$session" "$block" "$focus" "$effort" "$tabfocus" \
      </dev/null >>"$log" 2>&1
  else
    (trap '' HUP; exec nohup bash "$0" run "$dir" "$session" "$block" "$focus" "$effort" \
      "$tabfocus" </dev/null >>"$log" 2>&1) &
  fi
}

if [[ ${1:-} == run ]]; then
  shift
  [[ $# -eq 6 ]] || { echo 'usage: handoff.sh run DIR SESSION BLOCK FOCUS EFFORT focus|background' >&2; exit 2; }
  run "$@"
else
  [[ $# -eq 4 ]] || { echo "usage: handoff.sh DIR SESSION BLOCK CLIENT" >&2; exit 2; }
  popup "$1" "$2" "$3"
fi
