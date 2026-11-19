#!/usr/bin/env bash
# ctrl+b shift+x in Renux: stop a board orchestrator (board.sh stop). With one board
# running, stop it at once. With more, pick it with one key (1 to 9, in order).
#
#   board-stop.sh DIR SESSION BLOCK CLIENT
set -euo pipefail
# shellcheck source=SCRIPTDIR/board-popup.sh
source "$(dirname "$(readlink -f "$0")")/board-popup.sh"

board_popup "Stop a board orchestrator" stop running \
  'to_entries[] | "\(.key + 1)\t\(.value)"' "No board orchestrator runs." yes "${4:-}"
