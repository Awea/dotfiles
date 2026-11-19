#!/usr/bin/env bash
# ctrl+b shift+b in Renux: pick a board with one key, then show or start its orchestrator
# (board.sh open, which shows the session for this client).
#
#   board-open.sh DIR SESSION BLOCK CLIENT
set -euo pipefail
# shellcheck source=SCRIPTDIR/board-popup.sh
source "$(dirname "$(readlink -f "$0")")/board-popup.sh"

board_popup "Open a board orchestrator" open boards \
  '.[] | "\(.key)\t\(.board)"' "No board in the vault." no "${4:-}"
