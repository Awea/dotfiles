#!/usr/bin/env bash
# ctrl+b shift+l in Renux: the branch view (serie, a graph of the branches and their
# commits) of the repo of DIR, at once. When serie quits (q), a list of repos shows
# (branches-repos): Enter opens serie on the picked repo, Esc closes. Outside a repo, the
# list shows first. The Rex config runs this script in a new pane on the right, which
# closes when the script ends.
#
#   branches-pick.sh DIR SESSION BLOCK CLIENT
# No pipefail: fzf quits before branches-repos ends, and the pick is the exit status of fzf.
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
dir=${1:-$HOME}
here=$(dirname "$(readlink -f "$0")")

# show ROOT: serie on ROOT. -p kitty: Renux draws the graph with kitty images, and serie
# does not detect it alone. A serie error does not close the pane: the list shows again.
show() { serie -p kitty -C "$1" || true; }

if root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
  show "$root"
fi
while :; do
  picked=$("$here/branches-repos" "$dir" | sed "s|^$HOME|~|" |
    fzf --layout=reverse --prompt='branches> ' --header='Enter: open · Esc: close') || exit 0
  [[ -n $picked ]] || exit 0
  show "${picked/#\~/$HOME}"
done
