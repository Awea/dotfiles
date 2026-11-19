#!/usr/bin/env bash
# The folders of the Rex popups: the folder of a new claude tab (ctrl+b a) and the folders
# of a new session (ctrl+b N).
#
#   folders.sh main-folder DIR   the folder for a new tab from DIR
#   folders.sh folders           JSON list of the folders for a new session
set -euo pipefail
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

case "${1:-}" in
  main-folder) main_folder "${2:?usage: folders.sh main-folder DIR}" ;;
  folders) folders ;;
  *)
    printf 'usage: folders.sh main-folder DIR | folders\n' >&2
    exit 2
    ;;
esac
