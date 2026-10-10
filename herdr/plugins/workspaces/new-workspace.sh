#!/usr/bin/env bash
# Action new: choose a folder in a popup, then create a workspace in it.
#
#   new-workspace.sh open     action: open the folder popup
#   new-workspace.sh list     print the folders: ~/.workspace first, then the z folders
#   new-workspace.sh pick     popup: choose a folder with fzf, create the workspace
#
# The z folders come from the rupa/z data file ($_Z_DATA, ~/.z by default), the most
# frecent first. The popup shows $HOME as "~". Enter on an empty query picks
# ~/.workspace. Without ~/.workspace, $HOME is the first folder. Without fzf, the
# action creates the workspace in the first folder.
set -euo pipefail
# Herdr runs plugin commands with a small PATH. Add the system paths for fzf. On macOS,
# Homebrew puts fzf in /opt/homebrew/bin (Apple silicon) or /usr/local/bin.
export PATH="${PATH:-}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

H="${HERDR_BIN_PATH:-herdr}"
here="$(cd "$(dirname "$0")" && pwd)"

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
    dir=$(bash "$here/new-workspace.sh" list |
      fzf --reverse --tiebreak=index --prompt 'workspace> ' \
        --header 'Enter to create. Esc to cancel.') || exit 0
    "$H" workspace create --cwd "${dir/#\~/$HOME}" --focus >/dev/null
    ;;
  *)
    printf 'usage: new-workspace.sh open|list|pick\n' >&2
    exit 2
    ;;
esac
