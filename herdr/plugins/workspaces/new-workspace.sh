#!/usr/bin/env bash
# Action new: choose a folder in a popup, then create a workspace in it.
#
#   new-workspace.sh open     action: open the folder popup
#   new-workspace.sh list     print the folders: ~/.workspace first, then the z folders
#   new-workspace.sh pick     popup: choose a folder with fzf, create the workspace
#   new-workspace.sh worker DIR PROMPT [EFFORT] [--focus|--no-focus]
#                             worker: create the workspace, start claude, send the prompt
#
# The z folders come from the rupa/z data file ($_Z_DATA, ~/.z by default), the most
# frecent first. The popup shows $HOME as "~". Enter on an empty query picks
# ~/.workspace. Without ~/.workspace, $HOME is the first folder. Without fzf, the
# action creates the workspace in the first folder.
# Enter creates a shell workspace with the focus. ctrl+a asks for a prompt, an effort
# and the focus, as the agent-tabs new-tab action does, then starts claude in the
# workspace. The claude helpers come from the agent-tabs plugin.
set -euo pipefail
# Herdr runs plugin commands with a small PATH. Add the system paths for fzf. On macOS,
# Homebrew puts fzf in /opt/homebrew/bin (Apple silicon) or /usr/local/bin.
export PATH="${PATH:-}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

H="${HERDR_BIN_PATH:-herdr}"
here="$(cd "$(dirname "$0")" && pwd)"
agent_tabs="$here/../agent-tabs"

case "${1:-}" in
  open)
    if ! command -v fzf >/dev/null; then
      dir=$(bash "$here/new-workspace.sh" list | head -n 1)
      "$H" workspace create --cwd "${dir/#\~/$HOME}" --focus >/dev/null
      exit 0
    fi
    "$H" plugin pane open --plugin "$HERDR_PLUGIN_ID" --entrypoint pick >/dev/null
    ;;
  list)
    default="$HOME/.workspace"
    [ -d "$default" ] || default="$HOME"
    {
      printf '%s\n' "$default"
      # The frecency formula of rupa/z (z -l).
      if [ -f "${_Z_DATA:-$HOME/.z}" ]; then
        awk -F'|' -v now="$(date +%s)" '
          { print int(10000 * $2 * (3.75 / ((0.0001 * (now - $3) + 1) + 0.25))) "|" $1 }
        ' "${_Z_DATA:-$HOME/.z}" | sort -t'|' -k1,1nr | cut -d'|' -f2-
      fi
    } | awk '!seen[$0]++' | while IFS= read -r dir; do
      [ -d "$dir" ] || continue
      # Not ${dir/#$HOME/\~}: bash 3.2 (/bin/bash on macOS) keeps the backslash.
      case "$dir" in "$HOME" | "$HOME"/*) dir="~${dir#"$HOME"}" ;; esac
      printf '%s\n' "$dir"
    done
    ;;
  pick)
    # With --expect, fzf prints the key first: empty for Enter, else ctrl-a.
    picked=$(bash "$here/new-workspace.sh" list |
      fzf --reverse --tiebreak=index --prompt 'workspace> ' --expect=ctrl-a \
        --header 'Enter for a shell. ctrl+a for claude. Esc to cancel.') || exit 0
    key=$(head -n 1 <<<"$picked")
    dir=$(sed -n 2p <<<"$picked")
    [ -n "$dir" ] || exit 0
    dir="${dir/#\~/$HOME}"
    if [ "$key" != ctrl-a ]; then
      "$H" workspace create --cwd "$dir" --focus >/dev/null
      exit 0
    fi
    # shellcheck source=../agent-tabs/lib.sh source-path=SCRIPTDIR
    source "$agent_tabs/lib.sh"
    keys_hint
    prompt=$(read_line "Prompt for claude in $(basename "$dir") (Enter for a clean claude): ") || exit 0
    effort=$(read_effort) || exit 0
    focus=$(read_focus) || exit 0
    log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/new-workspace.log"
    setsid -f bash "$here/new-workspace.sh" worker "$dir" "$prompt" "$effort" "$focus" \
      </dev/null >>"$log" 2>&1
    ;;
  worker)
    dir="$2" prompt="$3" effort="${4:-}" focus="${5:---no-focus}"
    # shellcheck source=../agent-tabs/lib.sh source-path=SCRIPTDIR
    source "$agent_tabs/lib.sh"
    if ! created=$("$H" workspace create --cwd "$dir" "$focus") ||
      ! pane=$(jq -r '.result.root_pane.pane_id' <<<"$created") ||
      ! start_claude "$pane" "$effort"; then
      notify "Claude did not start in the new workspace."
      exit 1
    fi
    if [ -n "$prompt" ] && ! "$H" agent prompt "$pane" "$prompt" >/dev/null; then
      notify "Claude in $pane did not get the prompt."
      exit 1
    fi
    if [ -n "$prompt" ]; then
      name_agent "$pane" "$prompt"
    fi
    ;;
  *)
    printf 'usage: new-workspace.sh open|list|pick|worker DIR PROMPT [EFFORT] [--focus|--no-focus]\n' >&2
    exit 2
    ;;
esac
