# shellcheck shell=bash
# Shared helpers for the agent-tabs scripts. Source this file, do not run it.

# Herdr runs plugin commands with a small PATH. Add the system paths for jq. On macOS,
# Homebrew puts jq and bash 5 in /opt/homebrew/bin (Apple silicon) or /usr/local/bin.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# read_line and read_escape need bash 4 or later: $BASHPID, keyseq-timeout and read
# with a timeout of less than 1 second. /bin/bash on macOS is bash 3.2. When a script
# that sources this file runs under bash 3.2, run it again with the bash in PATH if that
# bash is newer. Without a newer bash, continue: only the popups do not work correctly.
# shellcheck disable=SC2016 # The other bash expands BASH_VERSINFO.
if [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ "${BASH_SOURCE[1]:-}" = "$0" ] &&
  "$(command -v bash)" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null; then
  # ${1+"$@"}: bash 3.2 with set -u stops on "$@" when there is no argument.
  exec "$(command -v bash)" "$0" ${1+"$@"}
fi

H="${HERDR_BIN_PATH:-herdr}"
# The herdr command of start_claude, open_claude_tab, workspace_pane and rename_agent.
# A script sets it to ("$H" --session NAME) to run them in another Herdr session.
HT=("$H")
# The hidden Herdr session of the workers of the board orchestrators. The orchestrators
# run in the session of the user.
BOARD_SESSION="${DISPATCH_SESSION:-board-workers}"

# The Herdr session of the pane that runs the script. HERDR_WORKSPACE_ID, HERDR_TAB_ID
# and HERDR_PANE_ID name IDs of that session.
PANE_SESSION="${HERDR_SESSION:-default}"

# Make plain "$H" call the session of the user from a pane of the hidden session
# $BOARD_SESSION (a worker that runs dispatch.sh). Herdr finds the session in
# HERDR_SESSION and HERDR_SOCKET_PATH, so remove them only for such a caller. A caller in
# another session keeps them. Only board.sh and dispatch.sh call this:
# sync-name.sh names the agent in the session of its own pane.
use_user_session() {
  [ "$PANE_SESSION" != "$BOARD_SESSION" ] || unset HERDR_SESSION HERDR_SOCKET_PATH
}

# Make sure the Herdr session $1 runs. When `herdr session list` does not show it as
# running, remove the file $2 (state of the old server, may be empty), then start the
# server detached, with exactly the environment of the default Herdr server: the file
# DISPATCH_SERVER_ENVIRON, else /proc/PID/environ of the process `<path>/herdr server`.
# The orchestrator has variables that a worker must not get (HERDR_*, CLAUDE*, a PATH
# with /usr/bin first). When there is no such environment, start the server through a
# login shell with a small environment. The server log goes to the board-orchestrator
# state folder. Wait DISPATCH_SESSION_WAIT seconds (10 by default) until the session
# answers. Return 1 with a message on stderr when it does not.
# A lock in the state folder keeps two calls from starting two servers. The server does
# not keep a lock of the caller on fd 7.
# When that environment has no DISPLAY and no WAYLAND_DISPLAY (an SSH session started
# the default server), add DISPLAY, XAUTHORITY and WAYLAND_DISPLAY of the desktop
# session: the file DISPATCH_DESKTOP_ENVIRON, else `systemctl --user show-environment`.
# Claude in a worker then copies a mouse selection with xclip or wl-copy. Without a
# display it sends OSC 52, and the hidden session drops it: it has no foreground client.
ensure_session() (
  s=$1 dir="${XDG_STATE_HOME:-$HOME/.local/state}/board-orchestrator"
  mkdir -p "$dir"
  exec 9>>"$dir/session-$s.lock"
  flock 9
  ! session_runs "$s" || exit 0
  [ -z "${2:-}" ] || rm -f "$2"
  environ=${DISPATCH_SERVER_ENVIRON:-}
  if [ -z "$environ" ]; then
    for f in /proc/[0-9]*/cmdline; do
      argv=()
      # The process can exit during the scan: hide the error of the redirect too.
      { mapfile -d '' -t argv <"$f"; } 2>/dev/null || continue
      if [ "${#argv[@]}" -eq 2 ] && [ "${argv[0]##*/}" = herdr ] && [ "${argv[1]}" = server ] &&
        [ -r "${f%cmdline}environ" ]; then
        environ=${f%cmdline}environ
        break
      fi
    done
  fi
  pairs=()
  [ -z "$environ" ] || [ ! -r "$environ" ] || mapfile -d '' -t pairs <"$environ" 2>/dev/null || pairs=()
  if [ "${#pairs[@]}" -gt 0 ]; then
    add_desktop_display pairs
    detach env -i "${pairs[@]}" "$H" --session "$s" server >>"$dir/server.log" 2>&1 </dev/null 7>&- 9>&-
  else
    small=()
    for v in HOME USER LOGNAME SHELL TERM LANG DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK $(compgen -e); do
      case "$v" in
        XDG_* | HOME | USER | LOGNAME | SHELL | TERM | LANG | DISPLAY | WAYLAND_DISPLAY | DBUS_SESSION_BUS_ADDRESS | SSH_AUTH_SOCK)
          [ -z "${!v+x}" ] || small+=("$v=${!v}")
          ;;
      esac
    done
    add_desktop_display small
    # shellcheck disable=SC2016 # The login shell expands $0 and $1.
    detach env -i ${small[@]+"${small[@]}"} "${SHELL:-/bin/sh}" -l -c 'exec "$0" --session "$1" server' "$H" "$s" \
      >>"$dir/server.log" 2>&1 </dev/null 7>&- 9>&-
  fi
  deadline=$((SECONDS + ${DISPATCH_SESSION_WAIT:-10}))
  until "$H" --session "$s" workspace list >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      printf 'dispatch: the Herdr session %s did not start. See %s.\n' "$s" "$dir/server.log" >&2
      exit 1
    fi
    sleep 0.2
  done
)

# Return 0 when `herdr session list` shows the Herdr session $1 as running.
session_runs() {
  [ -n "$("$H" session list --json 2>/dev/null |
    jq -r --arg s "$1" '.sessions[]? | select(.name == $s and .running == true) | .name' 2>/dev/null)" ]
}

# Add DISPLAY, XAUTHORITY and WAYLAND_DISPLAY of the desktop session to the array named
# $1 (VAR=value items), when it has no DISPLAY and no WAYLAND_DISPLAY. See ensure_session.
add_desktop_display() {
  local -n env_items=$1
  local item line
  for item in ${env_items[@]+"${env_items[@]}"}; do
    case "$item" in DISPLAY=?* | WAYLAND_DISPLAY=?*) return 0 ;; esac
  done
  while IFS= read -r line; do
    case "$line" in DISPLAY=?* | XAUTHORITY=?* | WAYLAND_DISPLAY=?*) env_items+=("$line") ;; esac
  done < <(if [ -n "${DISPATCH_DESKTOP_ENVIRON:-}" ]; then
    cat "$DISPATCH_DESKTOP_ENVIRON" 2>/dev/null
  else
    systemctl --user show-environment 2>/dev/null
  fi)
}

# Run the command $@ in the background, out of the session of the caller, so that it
# continues when the popup or the hook stops. macOS has no setsid: there, ignore SIGHUP
# before the fork. Herdr sends SIGHUP when the popup closes, and the caller often exits
# directly after detach: with nohup, SIGHUP can come before nohup ignores it and stop
# the command. The subshell keeps the trap out of the caller. The caller sets the
# redirections.
detach() {
  (
    # The command must not keep an open fd of the caller (a lock, or the output fd 3 of
    # bats): the caller then waits for ever.
    exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
    if command -v setsid >/dev/null; then
      setsid -f "$@"
    else
      trap '' HUP
      "$@" &
    fi
  )
}

# Print the time now in nanoseconds, for a Herdr seq. The macOS date has no %N. The
# bash variable EPOCHREALTIME has microseconds, with the decimal point of the locale.
now_ns() {
  printf '%s000\n' "${EPOCHREALTIME//[!0-9]/}"
}

# Print the mtime of FILE in seconds, with a fraction. GNU stat takes -c, the macOS
# stat takes -f. The decimal point depends on the system and the locale.
file_mtime() {
  stat -c %.9Y "$1" 2>/dev/null || stat -f %Fm "$1"
}

# Write MESSAGE to the plugin log. Show it as a Herdr notification only when the
# file debug exists in the plugin config dir.
notify() {
  if [ -e "${HERDR_PLUGIN_CONFIG_DIR:-}/debug" ]; then
    "$H" notification show "Agent tabs" --body "$1" >/dev/null 2>&1 || true
  fi
  printf 'agent-tabs: %s\n' "$1" >&2
}

# Show the message $1 to the user as a Herdr notification, also with no debug file, and
# write it to the plugin log. For a message that the user must see: notify shows a
# notification only in debug.
toast() {
  "$H" notification show "Agent tabs" --body "$1" >/dev/null 2>&1 || true
  printf 'agent-tabs: %s\n' "$1" >&2
}

# Print the lock file of the orchestrator start of board $1. board.sh worker holds it
# while it starts an orchestrator, and the stop holds it while it stops one: an open
# during a stop does not start a claude in a workspace that the stop then closes.
board_start_lock() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/board-orchestrator"
  mkdir -p "$dir"
  printf '%s\n' "$dir/board-$1.lock"
}

# Show a Herdr notification that the worker in pane $1 needs the user, with the body $3.
# The title has the agent name $2, or the pane ID when $2 is empty. Ignore a failure.
notify_need() {
  "$H" notification show "${2:-$1} needs you" --body "$3" --sound request >/dev/null 2>&1 || true
}

# Print the cwd of pane $1, in the Herdr session $2 when set. Print $HOME when Herdr
# gives no cwd.
pane_cwd() {
  local cwd
  cwd=$("$H" ${2:+--session "$2"} pane get "$1" | jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty') || cwd=""
  printf '%s\n' "${cwd:-$HOME}"
}

# Print the file name of pane $1 of the Herdr session $2 (the session of the script by
# default). Two Herdr servers can give the same pane ID, so a pane of a session other
# than default gets the session name first.
pane_key() {
  local session=${2:-$PANE_SESSION}
  if [ "$session" = default ]; then
    printf '%s\n' "${1//:/_}"
  else
    printf '%s.%s\n' "$session" "${1//:/_}"
  fi
}

# Print the path of the file that holds the worktree of the most recent work of the
# claude in pane $1 of the Herdr session $2. track-worktree.sh writes it and reviewr.sh
# reads it. The path uses only HOME, because a Herdr action runs with a small
# environment.
worktree_file() {
  printf '%s\n' "$HOME/.local/state/herdr/plugins/awea.agent-tabs/worktrees/$(pane_key "$@")"
}

# Print "SESSION PANE" when pane $1 is a view of a board worker: it runs
# `herdr --session SESSION agent attach PANE`. Print nothing for another pane.
view_worker() {
  "$H" pane process-info --pane "$1" 2>/dev/null | jq -r '
    first(.result.process_info.foreground_processes[].argv // []
      | select(length == 6 and .[1] == "--session" and .[3] == "agent" and .[4] == "attach"))
    | "\(.[2]) \(.[5])"
  ' 2>/dev/null || true
}

# Return 0 when pane $1 runs herdr-reviewr in the foreground. The label of a pane is
# not a proof: the argv of the process is.
is_reviewr() {
  "$H" pane process-info --pane "$1" 2>/dev/null | jq -e '
    any(.result.process_info.foreground_processes[];
      ((.argv0 // "") | split("/") | last) == "herdr-reviewr"
      or (((.argv // [])[0] // "") | split("/") | last) == "herdr-reviewr")
  ' >/dev/null
}

# Return 0 when a pane of the tab of pane $1 (the user session) runs reviewr.
reviewr_in_tab() {
  local tab p
  tab=$("$H" pane get "$1" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null) || return 1
  [ -n "$tab" ] || return 1
  while IFS= read -r p; do
    [ -z "$p" ] || [ "$p" = "$1" ] || ! is_reviewr "$p" || return 0
  done < <("$H" pane list 2>/dev/null | jq -r --arg t "$tab" '.result.panes[]? | select(.tab_id == $t) | .pane_id' 2>/dev/null)
  return 1
}

# Print the folder of the most recent work of the claude in pane $2 of the Herdr session
# $1: its worktree record, else the cwd of the pane.
work_dir() {
  local file dir="" other=""
  file=$(worktree_file "$2" "$1")
  [ ! -f "$file" ] || dir=$(head -n 1 "$file")
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    [ "$1" = "$PANE_SESSION" ] || other=$1
    dir=$(pane_cwd "$2" "$other")
  fi
  printf '%s\n' "$dir"
}

# Print the path of the file that holds the turn start of the claude in pane $1 of the
# Herdr session $2: one "ROOT<TAB>TREE" line for each worktree of the turn.
# track-worktree.sh writes it.
turn_file() {
  printf '%s\n' "$HOME/.local/state/herdr/plugins/awea.agent-tabs/turns/$(pane_key "$@")"
}

# Print the folder for a new tab from folder $1. In a linked git worktree, print the
# root of the main worktree. git lists the main worktree first. Else print $1: in the
# main worktree, outside a git repo, in a bare repo (it has no main worktree) and when
# git fails.
main_worktree() {
  local top main
  if top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) &&
    main=$(git -C "$1" worktree list --porcelain 2>/dev/null |
      awk 'NF == 0 { n++ } n == 0 && /^worktree / { path = substr($0, 10) }
        n == 0 && $0 == "bare" { bare = 1 } END { if (!bare) print path }') &&
    [ -n "$main" ] && [ "$(realpath "$top")" != "$(realpath "$main")" ]; then
    printf '%s\n' "$main"
  else
    printf '%s\n' "$1"
  fi
}

# Print the key reminder of the popups. In a terminal, print it dim on the last row
# and put the cursor back where it was.
keys_hint() {
  local hint="Enter to confirm. Esc or ctrl+c to cancel."
  if [ -t 2 ]; then
    printf '\e7\e[999;1H\e[2m%s\e[0m\e8' "$hint" >&2
  else
    printf '%s\n' "$hint" >&2
  fi
}

# Call after an Esc key. Return 1 for Esc alone. Read and ignore the rest of an
# escape sequence, for example an arrow key, and return 0.
read_escape() {
  local next
  IFS= read -r -s -n 1 -t 0.05 next || return 1
  case "$next" in
    # A CSI sequence ends with a byte from 64 (@) to 126 (~).
    "[")
      while IFS= read -r -s -n 1 -t 0.05 next; do
        next=$(printf '%d' "'$next")
        [ "$next" -ge 64 ] && [ "$next" -le 126 ] && break
      done
      ;;
    O) IFS= read -r -s -n 1 -t 0.05 next || true ;;
  esac
  return 0
}

# Insert a paste in the readline line. readline runs this function on the start
# of a bracketed paste. The function reads the text up to the paste end marker. It
# turns each newline into a space and inserts the text at the cursor.
read_paste() {
  local text
  IFS= read -r -d $'\e' text
  IFS= read -r -n 5 _
  text=${text//$'\r\n'/ }
  text=${text//[$'\r\n']/ }
  READLINE_LINE=${READLINE_LINE:0:READLINE_POINT}$text${READLINE_LINE:READLINE_POINT}
  READLINE_POINT=$((READLINE_POINT + ${#text}))
}

# Print PROMPT, read a line with readline, and print the line. Enter confirms. The
# readline keys edit the line, for example ctrl+w and alt+backspace delete a word.
# Return 1 on Esc and at the end of the input. A newline in a paste becomes a space,
# so only Enter confirms.
# Esc alone sends USR1 to this shell. readline waits 50 ms for the rest of an escape
# sequence, so the arrow keys and the alt keys still work.
read_line() {
  local line
  trap 'trap - USR1; return 1' USR1
  bind 'set keyseq-timeout 50' 2>/dev/null
  # shellcheck disable=SC2016 # readline runs the command, so $BASHPID expands then.
  bind -x '"\e": kill -USR1 $BASHPID' 2>/dev/null
  bind -x '"\e[200~": read_paste' 2>/dev/null
  IFS= read -r -e -p "$1" line || { trap - USR1; return 1; }
  trap - USR1
  printf '%s\n' "$line"
}

# Ask for the claude effort with one key. Print the level, or nothing for Enter
# and at the end of the input. Ask again after an incorrect key. Return 1 on Esc.
read_effort() {
  local key
  while true; do
    printf 'Effort [l]ow [m]edium [h]igh [x]high [M]ax (Enter for default): ' >&2
    IFS= read -r -s -n 1 key || key=""
    if [ "$key" = $'\e' ]; then
      if ! read_escape; then
        printf '\n' >&2
        return 1
      fi
      printf '\n' >&2
      continue
    fi
    printf '%s\n' "$key" >&2
    case "$key" in
      "") return 0 ;;
      l) echo low ;;
      m) echo medium ;;
      h) echo high ;;
      x) echo xhigh ;;
      M) echo max ;;
      *) continue ;;
    esac
    return 0
  done
}

# Ask with one key if the new tab gets the focus. Print --focus for y. Print --no-focus
# for n, for Enter and at the end of the input. Ask again after an incorrect key.
# Return 1 on Esc.
read_focus() {
  local key
  while true; do
    printf 'Focus the new tab? [y/N]: ' >&2
    IFS= read -r -s -n 1 key || key=""
    if [ "$key" = $'\e' ]; then
      if ! read_escape; then
        printf '\n' >&2
        return 1
      fi
      printf '\n' >&2
      continue
    fi
    printf '%s\n' "$key" >&2
    case "$key" in
      y | Y) echo --focus ;;
      "" | n | N) echo --no-focus ;;
      *) continue ;;
    esac
    return 0
  done
}

# Print the agent name of pane $1 while claude starts in it: "claude-start-" and the
# pane ID. Herdr names allow no ":" and no capitals, so ":" becomes "-" and a capital
# becomes "_" and its small letter: 2 pane IDs then never give the same name.
start_agent_name() {
  printf 'claude-start-%s\n' "$(sed 's/\([A-Z]\)/_\1/g; s/:/-/g' <<<"$1" | tr '[:upper:]' '[:lower:]')"
}

# Return 0 when $1 is a name that only marks a claude that starts: a start name, or
# "claude", the start name of older versions that panes still running can have.
placeholder_agent_name() {
  case "$1" in claude | claude-start-*) return 0 ;; esac
  return 1
}

# Start claude in pane $1. $2 is the claude effort level, empty for the claude default.
# Each next argument goes to claude as is.
# agent start needs a name that is unique in the Herdr session, so use the start name
# of the pane (start_agent_name) while it starts, then clear it. One fixed name would
# make a second start in the same session fail while the first one still runs.
# name_agent gives the real name.
# Clear the name also when the start fails: claude can still run in the pane, for
# example blocked at a question, and the start name then stays on it.
# Return 1 on failure: callers run it where set -e does not apply.
# In another Herdr session (HT has --session), first give the shell of the pane the
# desktop display when it has none: a hidden server that started with no display gives
# its panes none, and claude then cannot copy a mouse selection. See ensure_session.
start_claude() {
  local pane=$1 effort=${2:-} args=() display=() cmd
  shift $(($# < 2 ? $# : 2))
  [ -z "$effort" ] || args+=(--effort "$effort")
  args+=("$@")
  set -- "$pane"
  if [ "${#HT[@]}" -gt 1 ]; then
    add_desktop_display display
    if [ "${#display[@]}" -gt 0 ]; then
      printf -v cmd ' %q' "${display[@]}"
      # shellcheck disable=SC2016 # The shell of the pane expands the variables.
      "${HT[@]}" pane run "$1" '[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || export'"$cmd" >/dev/null 2>&1 || true
    fi
  fi
  # The shell of a new tab is not always at its prompt yet: Herdr then fails with
  # agent_pane_busy before it launches anything, so a retry is safe.
  local err tries=$((${AGENT_TABS_START_BUSY_WAIT:-10} * 5))
  until err=$("${HT[@]}" agent start "$(start_agent_name "$1")" --kind claude --pane "$1" --timeout 60000 \
    ${args[@]+-- "${args[@]}"} 2>&1 >/dev/null); do
    if [[ "$err" != *'"agent_pane_busy"'* ]] || [ "$tries" -le 0 ]; then
      printf '%s\n' "$err" >&2
      "${HT[@]}" agent rename "$1" --clear >/dev/null 2>&1 || true
      return 1
    fi
    tries=$((tries - 1))
    sleep 0.2
  done
  "${HT[@]}" agent rename "$1" --clear >/dev/null || true
}

# Open a tab in workspace $1 with cwd $2. $3 is --focus (the default) or --no-focus.
# $4 is the claude effort level, empty for the claude default.
# Each next argument goes to claude as is.
# Herdr gives the tab its number.
# Start claude in it and print the pane ID. Return 1 on failure.
open_claude_tab() {
  local created pane
  created=$("${HT[@]}" tab create --workspace "$1" --cwd "$2" "${3:---focus}") || return 1
  pane=$(jq -r '.result.root_pane.pane_id' <<<"$created") || return 1
  start_claude "$pane" "${4:-}" "${@:5}" || return 1
  printf '%s\n' "$pane"
}

# Print the ID of a pane where claude runs, in the Herdr workspace whose label is $1.
# $2 is the cwd, $3 is --focus or --no-focus, $4 is the claude effort level (may be empty),
# $5 is the fallback workspace ID. Each next argument goes to claude as is.
# When the workspace exists, open a tab in it. When there is none, or it closed before the
# tab create, create it and start claude in its root pane. When the tab create fails and
# the workspace is still there, return 1. When the lookup or the create fails, use workspace $5 and write
# a note to stderr (with an empty $5, write the note and return 1). When claude does not
# start, print the pane ID and return 1.
# With WS_LOCK set (a file), the lookup and the create run under a lock on that file, so
# that two calls do not create two workspaces with the same label.
# With WS_NO_START set, start no claude: print the pane, and the caller starts claude.
workspace_pane() {
  local label=$1 cwd=$2 focus=$3 effort=$4 fallback=$5 root rc=0
  shift 5
  # Exit 0 and print the root pane, exit 1, or exit 2 and print the note.
  root=$(
    if [ -n "${WS_LOCK:-}" ]; then
      exec 8>>"$WS_LOCK"
      flock 8
    fi
    if listing=$("${HT[@]}" workspace list 2>/dev/null) && ws=$(jq -r --arg l "$label" \
      '(.result.workspaces | if type == "array" then . else error("no array") end)
      | [.[] | select(.label == $l and (.workspace_id | type == "string" and . != "")) | .workspace_id][0] // ""' <<<"$listing" 2>/dev/null); then
      if [ -n "$ws" ]; then
        [ "$focus" != --focus ] || "${HT[@]}" workspace focus "$ws" >/dev/null 2>&1 || true
        # The workspace can close between the lookup and the tab create: then create it.
        if created=$("${HT[@]}" tab create --workspace "$ws" --cwd "$cwd" "$focus" 2>/dev/null); then
          jq -r '.result.root_pane.pane_id' <<<"$created" || exit 1
          exit 0
        fi
        # Create it only when it is gone: else two workspaces get the same label.
        if ! listing=$("${HT[@]}" workspace list 2>/dev/null) || [ -n "$(jq -r --arg l "$label" \
          '[.result.workspaces[]? | select(.label == $l)][0].workspace_id // empty' <<<"$listing" 2>/dev/null)" ]; then
          printf 'agent-tabs: could not open a tab in the workspace %s.\n' "$label" >&2
          exit 1
        fi
      fi
      # The root pane of the new workspace is the claude pane.
      if created=$("${HT[@]}" workspace create --cwd "$cwd" --label "$label" "$focus" 2>/dev/null) &&
        root=$(jq -r '.result.root_pane.pane_id // empty' <<<"$created" 2>/dev/null) && [ -n "$root" ]; then
        printf '%s\n' "$root"
        exit 0
      fi
      printf 'could not create the workspace for %s' "$label"
      exit 2
    fi
    printf 'workspace lookup failed'
    exit 2
  ) || rc=$?
  case "$rc" in
    0)
      if [ -z "${WS_NO_START:-}" ] && ! start_claude "$root" "$effort" "$@"; then
        printf '%s\n' "$root"
        return 1
      fi
      printf '%s\n' "$root"
      ;;
    2)
      if [ -z "$fallback" ]; then
        printf 'agent-tabs: %s.\n' "$root" >&2
        return 1
      fi
      printf 'agent-tabs: %s, using the current workspace.\n' "$root" >&2
      open_claude_tab "$fallback" "$cwd" "$focus" "$effort" "$@"
      ;;
    *) return 1 ;;
  esac
}

# Print the Obsidian vault path. Use OBSIDIAN_VAULT_PATH, else the same variable in the
# env of the claude user settings. Print nothing and return 1 when there is none.
vault_path() {
  local path=${OBSIDIAN_VAULT_PATH:-}
  if [ -z "$path" ] && [ -f "$HOME/.claude/settings.json" ]; then
    path=$(jq -r '.env.OBSIDIAN_VAULT_PATH // empty' "$HOME/.claude/settings.json" 2>/dev/null) || path=""
  fi
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Print the settings file $1 as one JSON object: {} for a missing or blank file.
# Exit 2 when the file is not one JSON object.
read_settings() {
  local out
  if [ ! -e "$1" ]; then
    printf '{}\n'
    return
  fi
  if ! out=$(jq -cs 'if length == 0 then {} elif length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' "$1" 2>/dev/null) || [ -z "$out" ]; then
    printf 'dispatch: %s is not valid JSON.\n' "$1" >&2
    exit 2
  fi
  printf '%s\n' "$out"
}

# Print the push policy of the folder $1 for dispatch.sh policy (deny, ask, allow or missing). Exit 2 for bad input.
push_policy() {
  local cwd="$1" f kind json
  local -a files=()
  if [ ! -d "$cwd" ]; then
    printf 'dispatch: %s is not a folder.\n' "$cwd" >&2
    exit 2
  fi
  for f in "$cwd/.claude/settings.json" "$cwd/.claude/settings.local.json"; do
    json=$(read_settings "$f") || exit 2
    files+=("$json")
  done
  for kind in deny ask allow; do
    for json in "${files[@]}"; do
      if [ "$(jq -r --arg k "$kind" \
        '[(.permissions | objects | .[$k]) // [] | arrays | .[] | strings | select(startswith("Bash(git push"))] | length > 0' \
        <<<"$json")" = true ]; then
        printf '%s\n' "$kind"
        return
      fi
    done
  done
  printf 'missing\n'
}

# Print $1 as a Herdr agent name: lowercase letters, digits and "-", with a letter first.
# Cut it at a word when it has more than 30 characters. That keeps 2 characters for "-N".
agent_slug() {
  local text
  text=$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs 'a-z0-9' '-')
  text=$(sed 's/^[^a-z]*//; s/-*$//' <<<"$text")
  if [ "${#text}" -gt 30 ]; then
    text="${text:0:30}"
    [[ "$text" != *-* ]] || text="${text%-*}"
  fi
  printf '%s\n' "$text"
}

# Give the claude in pane $1 its session title as agent name. Claude sets the title
# after the first prompt. Before that, the title is "claude" or "Claude Code".
# Wait for it AGENT_TABS_TITLE_TIMEOUT seconds (60 by default), then use $2.
# With no title and an empty $2, the agent keeps no name: start_claude cleared it.
# The name from $2 goes into the names file of the name listener: then the listener
# replaces it when claude gives a title later, for example after the trust prompt.
name_agent() {
  local agent title="" label deadline=$((SECONDS + ${AGENT_TABS_TITLE_TIMEOUT:-60}))
  while true; do
    if agent=$("$H" agent get "$1" 2>/dev/null); then
      title=$(jq -r '.result.agent.terminal_title_stripped // empty' <<<"$agent")
      case "$title" in "" | claude | "Claude Code") ;; *) break ;; esac
    fi
    title=""
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep 2
  done
  if [ -n "$title" ]; then
    rename_agent "$1" "$(agent_slug "$title")"
    return 0
  fi
  label=$(agent_slug "$2")
  [ -n "$label" ] || return 0
  rename_agent "$1" "$label"
  remember_agent_name "$(name_listener_file names)" "$1" "$label"
}

# Give the agent in pane $1 the name $2. Agent names must be unique. If the name is
# taken, add a number to it. Do nothing for an empty $2.
rename_agent() {
  local n
  [ -n "$2" ] || return 0
  "${HT[@]}" agent rename "$1" "$2" >/dev/null 2>&1 && return 0
  for n in 2 3 4 5 6 7 8 9; do
    "${HT[@]}" agent rename "$1" "$2-$n" >/dev/null 2>&1 && return 0
  done
  return 0
}

# Keep the agent name of the claude in pane $1 equal to its session title, also after
# /rename. Read the title every AGENT_TABS_SYNC_INTERVAL seconds (2 by default).
# Wait AGENT_TABS_START_TIMEOUT seconds (60 by default) for Herdr to find claude in the
# pane. Stop when claude exits. Keep the name while the title is a placeholder.
# A name that claude has when the loop first finds it comes from the caller, for
# example from `herdr agent start <name>`: keep it and stop. Herdr clears the name
# when claude exits, so a new claude in the pane gets the sync again.
sync_agent_name() {
  local kind name title label seen="" deadline=$((SECONDS + ${AGENT_TABS_START_TIMEOUT:-60}))
  while true; do
    kind=""
    IFS=$'\x1f' read -r kind name title < <("$H" agent get "$1" 2>/dev/null |
      jq -r '.result.agent | [.agent, .name // "", .terminal_title_stripped // ""] | join("\u001f")') || true
    if [ "$kind" = claude ]; then
      if [ -z "$seen" ] && [ -n "$name" ] && ! placeholder_agent_name "$name"; then
        return 0
      fi
      seen=1
      case "$title" in
        "" | claude | "Claude Code") ;;
        *)
          label=$(agent_slug "$title")
          if [ "$name" != "$label" ] && ! [[ "$name" =~ ^$label-[2-9]$ ]]; then
            rename_agent "$1" "$label"
          fi
          ;;
      esac
    elif [ -n "$seen" ] || [ "$SECONDS" -ge "$deadline" ]; then
      return 0
    fi
    sleep "${AGENT_TABS_SYNC_INTERVAL:-2}"
  done
}

# Give the claude in pane $1 its session title as agent name, once, for the session
# listener of sync-name.sh. The file $2 keeps the names that the sync gave, one
# "PANE NAME" line for each pane. A name that is not in that file and is not a
# placeholder (placeholder_agent_name) comes from the caller, for example from
# `herdr agent start <name>`: keep it. A name that matches the title goes into the
# file: then a listener after a restart, or a name from an old poll loop, follows the
# next /rename. Compare before the rename:
# each rename sends a pane event, also with the same name, and the listener must not
# wake itself in a loop.
sync_pane_name() {
  local kind="" name title label ours
  IFS=$'\x1f' read -r kind name title < <("$H" agent get "$1" 2>/dev/null |
    jq -r '.result.agent | [.agent, .name // "", .terminal_title_stripped // ""] | join("\u001f")') || true
  [ "$kind" = claude ] || return 0
  case "$title" in "" | claude | "Claude Code") return 0 ;; esac
  label=$(agent_slug "$title")
  [ -n "$label" ] || return 0
  ours=$(awk -v p="$1" '$1 == p { print $2 }' "$2" 2>/dev/null) || ours=""
  if [ "$name" = "$label" ] || [[ "$name" =~ ^$label-[2-9]$ ]]; then
    [ "$ours" = "$label" ] || remember_agent_name "$2" "$1" "$label"
    return 0
  fi
  if [ -n "$name" ] && ! placeholder_agent_name "$name" && { [ -z "$ours" ] ||
    { [ "$name" != "$ours" ] && ! [[ "$name" =~ ^$ours-[2-9]$ ]]; }; }; then
    return 0
  fi
  rename_agent "$1" "$label"
  remember_agent_name "$2" "$1" "$label"
}

# Print the path of the file $1 (lock, stamp or names) of the name listener of
# sync-name.sh for the Herdr session of the pane.
name_listener_file() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/herdr-agent-name-session-$PANE_SESSION.$1"
}

# Write the name $3 of pane $2 in the file $1 of sync_pane_name. An empty $3 removes
# the pane: Herdr clears the name when claude exits, and a new claude in the pane can
# get a name from `herdr agent start`.
remember_agent_name() {
  {
    awk -v p="$2" '$1 != p' "$1" 2>/dev/null || true
    [ -z "$3" ] || printf '%s %s\n' "$2" "$3"
  } >"$1.tmp" && mv "$1.tmp" "$1"
}

# Print the command that shows the pane $1 of the hidden session in a pane of the user.
attach_command() {
  local cmd
  printf -v cmd '%q --session %q agent attach %q' "$H" "$BOARD_SESSION" "$1"
  printf '%s\n' "$cmd"
}

# Return 0 when the pane $1 of the session of the user runs the attach of the pane $2 of
# the hidden session. With an empty $2, the attach of any pane of the hidden session.
# A view pane ID can be reused, or the attach can end.
runs_attach() {
  [ "$("$H" pane process-info --pane "$1" 2>/dev/null | jq -r --arg s "$BOARD_SESSION" --arg p "${2:-}" \
    '[.result.process_info.foreground_processes[]?.argv // []
      | select(length >= 5 and .[-5:-1] == ["--session", $s, "agent", "attach"] and ($p == "" or .[-1] == $p))]
      | length > 0' 2>/dev/null)" = true ]
}

# Print the boards whose workspace "<board> orchestrator" of the user holds the
# orchestrator claude (see orchestrator_pane), one for each line. Also take the label
# with a number of workers ("<board> orchestrator · 2 workers"). Return 1 when Herdr
# does not answer.
orchestrator_boards() {
  local listing agents board
  listing=$("$H" workspace list 2>/dev/null) || return 1
  agents=$("$H" agent list 2>/dev/null) || return 1
  while IFS= read -r board; do
    [ -z "$board" ] || ! orchestrator_pane "$board" >/dev/null || printf '%s\n' "$board"
  done < <(jq -rn --argjson w "$listing" --argjson a "$agents" \
    '[$a.result.agents[]? | select(.agent == "claude") | .workspace_id] as $ids
    | $w.result.workspaces[]? | select(.workspace_id as $i | $ids | index([$i]))
    | (.label // "") | sub(" · .*$"; "") | select(endswith(" orchestrator")) | sub(" orchestrator$"; "")' 2>/dev/null)
}

# Print the pane of the orchestrator claude of the board $1: in the workspace
# "$1 orchestrator" of the user, the claude whose name is the agent slug of
# "$1-orchestrator", or that slug with "-N" added. Another claude there belongs to the
# user, and a worker view there runs the attach, not claude. Return 1 when there is no
# orchestrator, or when the lookup fails.
orchestrator_pane() {
  local ws pane
  ws=$(board_workspace_id "$1") || return 1
  [ -n "$ws" ] || return 1
  pane=$("$H" agent list 2>/dev/null | jq -r --arg w "$ws" --arg n "$(agent_slug "$1-orchestrator")" \
    '[.result.agents[]? | select(.workspace_id == $w and .agent == "claude")
      | select((.name // "") as $m | $m == $n or ($m | startswith($n + "-")
        and (.[($n | length) + 1:] | test("^[0-9]+$"))))][0].pane_id // empty' 2>/dev/null)
  [ -n "$pane" ] || return 1
  printf '%s\n' "$pane"
}

# The jq test for the workspace "$l" of the user: the label, or the label with a number
# of workers ("$l · 2 workers"), from a version that put the number in the label.
# shellcheck disable=SC2016 # jq expands $l.
BOARD_WS_MATCH='select(.label == $l or ((.label // "") | startswith($l + " · ")))'

# Print the ID of the workspace "$1 orchestrator" in the session of the user, or nothing.
# Return 1 when the lookup fails.
board_workspace_id() {
  local listing
  listing=$("$H" workspace list 2>/dev/null) || return 1
  jq -r --arg l "$1 orchestrator" \
    "[.result.workspaces[]? | $BOARD_WS_MATCH | .workspace_id][0] // empty" <<<"$listing" 2>/dev/null
}

# Show the number of claude workers of board $1 (in the workspace "$1 workers" of the
# hidden session) on the workspace "$1 orchestrator" of the user, as its metadata token
# "workers": "2 workers". herdr/config.toml shows the token on the second line of the
# workspace, in the place of the git branch. The token "working" gives the number of
# workers that work ("1 working"), and the config shows it in yellow. The counts are
# tokens, not a reported agent: an agent shows in the agent list, and a count does not
# wait for the user. Give a label with a number back its plain name. Ignore a failure: this
# is only a hint. Herdr shows a claude as idle when its turn ends, also when a background
# agent or a background shell of that claude still works. So read the screen of each idle
# or done worker. Count it as working when the agent list of Claude Code shows a
# background agent (a row that starts with "◯"). Also count it as working when the footer
# shows a running shell ("1 shell" or "3 shells"). The footer is the lines after the last
# line that starts with "─". Text of the transcript above the input box does not count.
# The footer part "← 1 agent" shows also with no background agent: do not use it. A
# failed read counts as not working.
show_worker_count() {
  local listing ws current hidden agents n working text tokens p label="$1 orchestrator"
  listing=$("$H" workspace list 2>/dev/null) || return 0
  IFS=$'\t' read -r ws current < <(jq -r --arg l "$label" \
    "[.result.workspaces[]? | $BOARD_WS_MATCH][0] // empty | [.workspace_id, .label] | @tsv" <<<"$listing" 2>/dev/null) ||
    return 0
  hidden=$("$H" --session "$BOARD_SESSION" workspace list 2>/dev/null) || return 0
  agents=$("$H" --session "$BOARD_SESSION" agent list 2>/dev/null) || return 0
  # jq 1.6 (/usr/bin/jq first in PATH) does not take $label or $or as a name.
  read -r n working < <(jq -rn --argjson w "$hidden" --argjson a "$agents" --arg l "$1 workers" '
    ([$w.result.workspaces[]? | select(.label == $l) | .workspace_id][0] // "") as $wk
    | [$a.result.agents[]? | select($wk != "" and .workspace_id == $wk and .agent == "claude")] as $all
    | "\($all | length) \([$all[] | select(.agent_status == "working")] | length)",
      ($all[] | select(.agent_status == "idle" or .agent_status == "done") | .pane_id)
  ' 2>/dev/null | {
    read -r n working || exit 1
    while IFS= read -r p; do
      "$H" --session "$BOARD_SESSION" pane read "$p" --source visible </dev/null 2>/dev/null | tail -n 15 |
        awk '/^ +◯ / { agent = 1 } /^─/ { shell = 0; next } / · [0-9]+ shells?( ·|$)/ { shell = 1 }
          END { exit !(agent || shell) }' &&
        working=$((working + 1))
    done
    echo "$n $working"
  }) || return 0
  text="$n workers"
  [ "$n" != 1 ] || text="1 worker"
  tokens=(--token "workers=$text" --clear-token working)
  [ "$working" -eq 0 ] || tokens=(--token "workers=$text" --token "working=$working working")
  "$H" workspace report-metadata "$ws" --source board-orchestrator "${tokens[@]}" \
    --seq "$(now_ns)" >/dev/null 2>&1 || true
  [ "$label" = "$current" ] || "$H" workspace rename "$ws" "$label" >/dev/null 2>&1 || true
}
