#!/usr/bin/env bash
# Shell work of the ctrl+b keys of herdr-app (the prefix mod and its popups). Ported from
# the Herdr 0.9.5 plugins agent-tabs and workspaces, which Herdr 0.9.5 still runs.
#
#   agent-tabs.sh main-folder DIR   the folder for a new tab from DIR
#   agent-tabs.sh folders           JSON list of the folders for a new space
#   agent-tabs.sh handoff TERMINAL SPACE TAB FOCUS EFFORT focus|background
#                                   run /handoff in TERMINAL, then continue in a new tab
#   agent-tabs.sh reviewr DIR [BASE]
#                                   run herdr-reviewr on DIR, with herdr-shim as its herdr,
#                                   in the branch scope on BASE when BASE is given
#   agent-tabs.sh handoff-start ARGS...
#                                   run handoff ARGS detached, with a log file
set -euo pipefail
HC=("${HC_BIN:-hc}")
HAPP=("${HERDR_APP_BIN:-herdr-app}")
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# main_folder DIR: in a linked git worktree, the root of the main worktree (git lists it
# first). Else DIR: in the main worktree, outside a git repo, in a bare repo, when git
# fails and when the main worktree folder is gone.
main_folder() {
  local top main
  if top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) &&
    main=$(git -C "$1" worktree list --porcelain 2>/dev/null |
      awk 'NF == 0 { n++ } n == 0 && /^worktree / { path = substr($0, 10) }
        n == 0 && $0 == "bare" { bare = 1 } END { if (!bare) print path }') &&
    [ -n "$main" ] && [ -d "$main" ] && [ "$(cd "$top" && pwd -P)" != "$(cd "$main" && pwd -P)" ]; then
    printf '%s\n' "$main"
  else
    printf '%s\n' "$1"
  fi
}

# folders: ~/.workspace (else $HOME) first, then the z folders, most frecent first, with
# no duplicate and no missing folder.
folders() {
  local default="$HOME/.workspace" z="${_Z_DATA:-$HOME/.z}"
  [ -d "$default" ] || default="$HOME"
  {
    printf '%s\n' "$default"
    # The frecency formula of rupa/z (z -l).
    if [ -f "$z" ]; then
      awk -F'|' -v now="$(date +%s)" '
        { print int(10000 * $2 * (3.75 / ((0.0001 * (now - $3) + 1) + 0.25))) "|" $1 }
      ' "$z" | sort -t'|' -k1,1nr | cut -d'|' -f2-
    fi
  } | awk '!seen[$0]++' | while IFS= read -r dir; do
    [ ! -d "$dir" ] || printf '%s\n' "$dir"
  done | jq -Rn '[inputs]'
}

# json_array ARGS...: a JSON array of the arguments, one for each line (an argument has
# no newline: the popups read one line). Not jq --args: jq reads an argument such as
# --effort as its own option.
json_array() { printf '%s\n' "$@" | jq -Rnc '[inputs]'; }

log_file() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-app"
  mkdir -p "$dir"
  printf '%s/handoff.log\n' "$dir"
}

# fail_tab SPACE FOLDER ERROR: the result of a failed handoff, where the user waits for
# the new tab: a shell tab that prints the error and the log path (no toast).
fail_tab() {
  printf '%s\n' "$3" >&2
  "${HAPP[@]}" "do" tab.new --space "$1" --folder "$2" --name "handoff failed" \
    --argv "$(jq -cn --arg e "$3" --arg l "$(log_file)" \
      '["sh", "-c", "printf \"%s\\n\" \"$0\" \"Log: $1\"; exec \"${SHELL:-sh}\"", $e, $l]')" >/dev/null || true
  return 1
}

# state TERMINAL: the agent status of TERMINAL (idle, working, blocked, done), or empty.
state() { "${HC[@]}" get "$1" --json 2>/dev/null | jq -r '.status.state // empty' 2>/dev/null || true; }

# handoff TERMINAL SPACE TAB FOCUS EFFORT TABFOCUS: as handoff.sh worker of agent-tabs.
# A failure before the new claude tab opens a shell tab that prints the error.
handoff() {
  local term=$1 space=$2 tab=$3 focus=$4 effort=$5 tabfocus=$6 json status cwd doc title
  local deadline st argv=()
  json=$("${HC[@]}" get "$term" --json 2>/dev/null) || json='{}'
  # The new tab opens in the folder of the source, as the old handoff did.
  cwd=$(jq -r '.foreground.cwd // .cwd // empty' <<<"$json")
  cwd=${cwd:-$HOME}
  status=$(jq -r 'if .state == "live" and .status.app == "claude-code" then .status.state else "" end' <<<"$json")
  if [ "$status" != idle ] && [ "$status" != "done" ]; then
    fail_tab "$space" "$cwd" "$term is not an idle claude (status: ${status:-none}). The handoff did not start."
    return 1
  fi
  doc="${TMPDIR:-/tmp}/herdr-handoff-$(date +%Y%m%d-%H%M%S)-$$.md"
  # The title of the new session: the focus, else the source title with "handoff".
  # Without it, claude makes a title from the first prompt, the same for each handoff.
  title=$focus
  if [ -z "$title" ]; then
    title=$(jq -r '.title // empty' <<<"$json")
    case "$title" in "" | claude | "Claude Code") title="" ;; *) title="$title handoff" ;; esac
  fi
  # --wait waits for the turn that the send starts. The turn can stop at a permission
  # prompt (blocked): wait again until the source is idle or done, up to 15 minutes.
  deadline=$((SECONDS + ${AGENT_TABS_HANDOFF_WAIT:-900}))
  "${HC[@]}" send --wait --timeout "${AGENT_TABS_HANDOFF_WAIT:-900}" "$term" \
    "/handoff ${focus:+$focus. }Save the handoff document to $doc" >/dev/null 2>&1 || true
  while :; do
    st=$(state "$term")
    if [ -z "$st" ] || [ "$st" = idle ] || [ "$st" = "done" ]; then break; fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      fail_tab "$space" "$cwd" "The handoff of $term did not end in 15 minutes."
      return 1
    fi
    # hc wait ends at once on a terminal that is already blocked: poll gently while the
    # permission prompt waits for the user.
    if [ "$st" = blocked ]; then
      sleep 2
    else
      "${HC[@]}" wait "$term" --timeout $((deadline - SECONDS > 0 ? deadline - SECONDS : 1)) >/dev/null 2>&1 || true
    fi
  done
  [ -s "$doc" ] || { fail_tab "$space" "$cwd" "The agent in $term did not write $doc."; return 1; }
  argv=(claude)
  [ -z "$title" ] || argv+=(-n "$title")
  [ -z "$effort" ] || argv+=(--effort "$effort")
  "${HAPP[@]}" "do" tab.new --space "$space" --folder "$cwd" \
    --argv "$(json_array "${argv[@]}")" \
    --task "Read the handoff document at $doc, then continue the work." >/dev/null || return 1
  [ "$tabfocus" != background ] || "${HAPP[@]}" "do" tab.select --id "$tab" >/dev/null || true
}

# reviewr_bin: herdr-reviewr from PATH, else from the Herdr 0.9.5 plugin install.
reviewr_bin() {
  local f
  if [ -n "${REVIEWR_BIN:-}" ]; then printf '%s\n' "$REVIEWR_BIN"; return; fi
  if command -v herdr-reviewr >/dev/null 2>&1; then command -v herdr-reviewr; return; fi
  for f in "$HOME"/.config/herdr/plugins/github/persiyanov.reviewr-*/bin/herdr-reviewr; do
    [ -x "$f" ] && printf '%s\n' "$f" && return
  done
  return 1
}

# reviewr DIR [BASE]: run herdr-reviewr in this hc terminal. Its herdr calls go to
# herdr-shim, with the herdr-app space, tab and terminal of this terminal as the Herdr ids.
# With BASE: the branch scope on BASE (herdr-app/reviewr-branch/config.toml, --base).
reviewr() {
  local bin labels here config=reviewr
  local -a flags=()
  here="$(cd "$(dirname "$0")" && pwd)"
  if [ -n "${2:-}" ]; then
    config=reviewr-branch
    flags=(--base "$2")
  fi
  if ! bin=$(reviewr_bin); then
    printf 'agent-tabs: herdr-reviewr is not installed.\n' >&2
    exec "${SHELL:-sh}"
  fi
  labels=$("${HC[@]}" get "${HC_TERMINAL_ID:-}" --json 2>/dev/null | jq -c '.labels // {}') || labels='{}'
  HERDR_BIN_PATH="$here/herdr-shim" \
    HERDR_WORKSPACE_ID=$(jq -r '.["herdr.space"] // empty' <<<"$labels") \
    HERDR_TAB_ID=$(jq -r '.["herdr.tab"] // empty' <<<"$labels") \
    HERDR_PANE_ID=${HC_TERMINAL_ID:-} \
    HERDR_PLUGIN_CONFIG_DIR="$(cd "$here/../$config" && pwd)" \
    exec "$bin" ${flags[@]+"${flags[@]}"} "$1"
}

case "${1:-}" in
  main-folder) main_folder "${2:?usage: agent-tabs.sh main-folder DIR}" ;;
  folders) folders ;;
  reviewr) reviewr "${2:?usage: agent-tabs.sh reviewr DIR [BASE]}" "${3:-}" ;;
  handoff)
    [ "$#" -eq 7 ] || { printf 'usage: agent-tabs.sh handoff TERMINAL SPACE TAB FOCUS EFFORT focus|background\n' >&2; exit 2; }
    handoff "$2" "$3" "$4" "$5" "$6" "$7"
    ;;
  handoff-start)
    shift
    # Detached: the mod that calls this closes at once. No setsid on macOS.
    log=$(log_file)
    (
      trap '' HUP
      exec nohup bash "$0" handoff "$@" </dev/null >>"$log" 2>&1
    ) &
    ;;
  *)
    printf 'usage: agent-tabs.sh main-folder DIR|folders|handoff ...\n' >&2
    exit 2
    ;;
esac
