#!/usr/bin/env bash
# Action new-shell-tab: open a shell tab with the focus, without claude.
#
#   new-shell-tab.sh                        action: open the tab
#
# The tab starts in the folder of the focused pane. In a linked git worktree, the tab
# starts in the root of the main worktree of the repo. Without a focused pane, Herdr
# gives the tab its default folder.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

if [ -z "${HERDR_WORKSPACE_ID:-}" ]; then
  notify "No workspace has focus. Focus a workspace, then try again."
  exit 1
fi
cwd=()
if [ -n "${HERDR_PANE_ID:-}" ]; then
  cwd=(--cwd "$(main_worktree "$(pane_cwd "$HERDR_PANE_ID")")")
fi
if ! "$H" tab create --workspace "$HERDR_WORKSPACE_ID" ${cwd[@]+"${cwd[@]}"} --focus >/dev/null; then
  notify "The new tab did not open."
  exit 1
fi
