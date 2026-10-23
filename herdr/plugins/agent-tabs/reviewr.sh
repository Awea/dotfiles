#!/usr/bin/env bash
# Action reviewr: open a reviewr pane right of the focused pane, for the git worktree of
# the most recent work of claude in that pane. The tab zooms on reviewr.
#
#   reviewr.sh    action: prefix+d runs it
#
# The hook track-worktree.sh records the worktree of each pane. Without a record, or
# when the recorded folder no longer exists, the action uses the cwd of the pane.
#
# The reviewr action "open" allows one reviewr in each workspace and uses the cwd of the
# focused pane. This action opens one next to the pane. When the tab already has one for
# the same worktree, the action zooms on it. When the focused pane is a reviewr, the
# action does nothing.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

if [ -z "${HERDR_PANE_ID:-}" ]; then
  notify "reviewr: no pane has focus."
  exit 1
fi

# Return 0 when pane $1 runs herdr-reviewr in the foreground. The label of a pane is
# not a proof.
is_reviewr() {
  "$H" pane process-info --pane "$1" 2>/dev/null | jq -e '
    any(.result.process_info.foreground_processes[];
      ((.argv0 // "") | split("/") | last) == "herdr-reviewr"
      or (((.argv // [])[0] // "") | split("/") | last) == "herdr-reviewr")
  ' >/dev/null
}

if is_reviewr "$HERDR_PANE_ID"; then
  notify "reviewr: the focused pane is a reviewr."
  exit 0
fi
dir=""
file=$(worktree_file "$HERDR_PANE_ID")
[ ! -f "$file" ] || dir=$(head -n 1 "$file")
[ -n "$dir" ] && [ -d "$dir" ] || dir=$(pane_cwd "$HERDR_PANE_ID")
if ! root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
  notify "reviewr: $dir is not in a git repo."
  exit 1
fi

# Find a reviewr pane in the tab of the focused pane with the same worktree. Zoom on it.
# Herdr has no command to focus a pane by ID, and the zoom shows the pane.
panes=$("$H" pane list ${HERDR_WORKSPACE_ID:+--workspace "$HERDR_WORKSPACE_ID"}) || panes='{}'
candidates=$(jq -r --arg me "$HERDR_PANE_ID" --arg root "$root" '
  (.result.panes // []) as $all
  | (first($all[] | select(.pane_id == $me) | .tab_id) // "") as $tab
  | $all[] | select(.tab_id == $tab and .pane_id != $me and .foreground_cwd == $root) | .pane_id
' <<<"$panes") || candidates=""
for pane in $candidates; do
  if is_reviewr "$pane"; then
    "$H" pane zoom "$pane" --on >/dev/null 2>&1 || true
    notify "reviewr: pane $pane already shows $root in this tab."
    exit 0
  fi
done

if ! opened=$("$H" plugin pane open --plugin persiyanov.reviewr --entrypoint pane \
  --placement zoomed --target-pane "$HERDR_PANE_ID" --direction right --cwd "$root" --focus 2>&1); then
  notify "reviewr: Herdr did not open the pane: $opened"
  exit 1
fi
notify "reviewr: opened pane $(jq -r '.result.plugin_pane.pane.pane_id // "?"' <<<"$opened") for $root."
