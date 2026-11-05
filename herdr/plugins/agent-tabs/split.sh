#!/usr/bin/env bash
# Actions split-right and split-down: split the focused pane, as the Herdr split keys do.
#
#   split.sh right|down      action: prefix+% runs it with right, prefix+" with down
#
# A view of a board worker runs `herdr --session S agent attach PANE` in the home folder,
# and a Herdr split opens in the folder of the split pane. So in a view, the new pane
# opens in the worktree of the worker: its record, else its cwd. Another pane keeps the
# folder that Herdr gives.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

direction=${1:-}
case "$direction" in
  right | down) ;;
  *)
    printf 'usage: split.sh right|down\n' >&2
    exit 2
    ;;
esac
if [ -z "${HERDR_PANE_ID:-}" ]; then
  notify "split: no pane has focus."
  exit 1
fi
cwd=()
if attach=$(view_worker "$HERDR_PANE_ID") && [ -n "$attach" ]; then
  read -r session pane <<<"$attach"
  cwd=(--cwd "$(work_dir "$session" "$pane")")
fi
"$H" pane split "$HERDR_PANE_ID" --direction "$direction" ${cwd[@]+"${cwd[@]}"} --focus >/dev/null
