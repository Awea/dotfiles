# shellcheck shell=bash
# Shared helpers for the agent-tabs scripts. Source this file, do not run it.

# Herdr runs plugin commands with a small PATH. Add the system paths for jq.
export PATH="/usr/bin:/bin:${PATH:-}"

H="${HERDR_BIN_PATH:-herdr}"

# Write MESSAGE to the plugin log. Show it as a Herdr notification only when the
# file debug exists in the plugin config dir.
notify() {
  if [ -e "${HERDR_PLUGIN_CONFIG_DIR:-}/debug" ]; then
    "$H" notification show "Agent tabs" --body "$1" >/dev/null 2>&1 || true
  fi
  printf 'agent-tabs: %s\n' "$1" >&2
}

# Print the cwd of pane $1. Print $HOME when Herdr gives no cwd.
pane_cwd() {
  local cwd
  cwd=$("$H" pane get "$1" | jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty') || cwd=""
  printf '%s\n' "${cwd:-$HOME}"
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

# Print PROMPT, read a line with readline, and print the line. Enter confirms. The
# readline keys edit the line, for example ctrl+w and alt+backspace delete a word.
# Return 1 on Esc and at the end of the input.
# Esc alone sends USR1 to this shell. readline waits 50 ms for the rest of an escape
# sequence, so the arrow keys and the alt keys still work.
read_line() {
  local line
  trap 'trap - USR1; return 1' USR1
  bind 'set keyseq-timeout 50' 2>/dev/null
  # shellcheck disable=SC2016 # readline runs the command, so $BASHPID expands then.
  bind -x '"\e": kill -USR1 $BASHPID' 2>/dev/null
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

# Open a tab in workspace $1 with cwd $2. $3 is --focus (the default) or --no-focus.
# $4 is the claude effort level, empty for the claude default.
# Herdr gives the tab its number.
# Start claude in it and print the pane ID. agent start needs a unique name, so use
# the name "claude" while it starts, then clear it. name_agent gives the real name.
# Return 1 on failure: callers run it where set -e does not apply.
open_claude_tab() {
  local created pane
  created=$("$H" tab create --workspace "$1" --cwd "$2" "${3:---focus}") || return 1
  pane=$(jq -r '.result.root_pane.pane_id' <<<"$created") || return 1
  "$H" agent start claude --kind claude --pane "$pane" --timeout 60000 \
    ${4:+-- --effort "$4"} >/dev/null || return 1
  "$H" agent rename "$pane" --clear >/dev/null || true
  printf '%s\n' "$pane"
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
# With no title and an empty $2, the sidebar keeps the name "claude".
name_agent() {
  local agent title="" deadline=$((SECONDS + ${AGENT_TABS_TITLE_TIMEOUT:-60}))
  while true; do
    if agent=$("$H" agent get "$1" 2>/dev/null); then
      title=$(jq -r '.result.agent.terminal_title_stripped // empty' <<<"$agent")
      case "$title" in "" | claude | "Claude Code") ;; *) break ;; esac
    fi
    title=""
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep 2
  done
  title="${title:-$2}"
  [ -n "$title" ] || return 0
  rename_agent "$1" "$(agent_slug "$title")"
}

# Give the agent in pane $1 the name $2. Agent names must be unique. If the name is
# taken, add a number to it. Do nothing for an empty $2.
rename_agent() {
  local n
  [ -n "$2" ] || return 0
  "$H" agent rename "$1" "$2" >/dev/null 2>&1 && return 0
  for n in 2 3 4 5 6 7 8 9; do
    "$H" agent rename "$1" "$2-$n" >/dev/null 2>&1 && return 0
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
      if [ -z "$seen" ] && [ -n "$name" ] && [ "$name" != claude ]; then
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
