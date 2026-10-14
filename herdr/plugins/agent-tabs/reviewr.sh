#!/usr/bin/env bash
# The /reviewr command of claude: open a reviewr pane right of the claude pane, for the
# git worktree of claude. The tab zooms on reviewr.
#
#   reviewr.sh [DIR]    DIR is a folder of the worktree. Without DIR, the current folder.
#
# The skill tells claude to give DIR: claude knows the worktree where it works.
#
# The reviewr action "open" allows one reviewr in each workspace and uses the cwd of the
# focused pane. This script opens one next to claude, unless the tab already has one for
# the same worktree.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

if [ "${HERDR_ENV:-}" != 1 ] || [ -z "${HERDR_PANE_ID:-}" ]; then
  echo "reviewr: run /reviewr in a Herdr pane."
  exit 1
fi
dir="${1:-$PWD}"
if ! root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
  echo "reviewr: $dir is not in a git repo."
  exit 1
fi

# Find a reviewr pane in the tab of claude with the same worktree. A reviewr pane runs
# herdr-reviewr in the foreground. Its label is not a proof.
panes=$("$H" pane list ${HERDR_WORKSPACE_ID:+--workspace "$HERDR_WORKSPACE_ID"}) || panes='{}'
candidates=$(jq -r --arg me "$HERDR_PANE_ID" --arg root "$root" '
  (.result.panes // []) as $all
  | (first($all[] | select(.pane_id == $me) | .tab_id) // "") as $tab
  | $all[] | select(.tab_id == $tab and .pane_id != $me and .foreground_cwd == $root) | .pane_id
' <<<"$panes") || candidates=""
for pane in $candidates; do
  if "$H" pane process-info --pane "$pane" 2>/dev/null | jq -e '
    any(.result.process_info.foreground_processes[];
      ((.argv0 // "") | split("/") | last) == "herdr-reviewr"
      or (((.argv // [])[0] // "") | split("/") | last) == "herdr-reviewr")
  ' >/dev/null; then
    echo "reviewr: pane $pane already shows $root in this tab."
    exit 0
  fi
done

if ! opened=$("$H" plugin pane open --plugin persiyanov.reviewr --entrypoint pane \
  --placement zoomed --target-pane "$HERDR_PANE_ID" --direction right --cwd "$root" --focus 2>&1); then
  echo "reviewr: Herdr did not open the pane: $opened"
  exit 1
fi
echo "reviewr: opened pane $(jq -r '.result.plugin_pane.pane.pane_id // "?"' <<<"$opened") for $root."
