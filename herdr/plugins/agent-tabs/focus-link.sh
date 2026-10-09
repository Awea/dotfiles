#!/usr/bin/env bash
# Action focus-link: focus the pane or the tab of a clicked Herdr link.
#
#   focus-link.sh                           action: the link handler herdr-link runs it
#
# A Herdr link has the form https://herdr.invalid/pane/<pane ID> or
# https://herdr.invalid/tab/<tab ID>. The host herdr.invalid never resolves, so a click
# without the plugin opens nothing useful. Herdr has no API to focus a pane by ID: the
# action focuses the tab of the pane, then the agent in the pane, if the pane has one.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

url="${HERDR_PLUGIN_CLICKED_URL:-}"
if ! [[ "$url" =~ ^https://herdr\.invalid/(pane|tab)/([A-Za-z0-9]+:[A-Za-z0-9]+)$ ]]; then
  notify "Not a Herdr pane or tab link: $url"
  exit 1
fi
kind="${BASH_REMATCH[1]}" id="${BASH_REMATCH[2]}"
tab="$id"
if [ "$kind" = pane ]; then
  if ! tab=$("$H" pane get "$id" 2>/dev/null | jq -er '.result.pane.tab_id'); then
    notify "The pane $id does not exist."
    exit 1
  fi
fi
if ! "$H" tab focus "$tab" >/dev/null 2>&1; then
  notify "The $kind $id does not exist."
  exit 1
fi
[ "$kind" = tab ] || "$H" agent focus "$id" >/dev/null 2>&1 || true
