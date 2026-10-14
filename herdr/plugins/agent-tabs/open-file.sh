#!/usr/bin/env bash
# Action open-file: open the file of a clicked file link in Sublime Text.
#
#   open-file.sh                            action: the link handler file-link runs it
#
# A file link has the form file://<host>/<path>, with an optional line as :<line> or
# #L<line>. Herdr opens only http(s) links itself, so a click on a file link opens
# nothing without the plugin. The action does not use $EDITOR: its -n opens a second
# window next to the window that Sublime Text restores. AGENT_TABS_EDITOR replaces
# subl, for the tests.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

url="${HERDR_PLUGIN_CLICKED_URL:-}"
if ! [[ "$url" =~ ^file://[^/]*(/[^#:]*)(:([0-9]+)|#L([0-9]+))?$ ]]; then
  notify "Not a file link: $url"
  exit 1
fi
path="${BASH_REMATCH[1]}" line="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
# Decode the percent escapes, for example %20 for a space.
path=$(printf '%b' "${path//%/\\x}")
if ! [ -e "$path" ]; then
  notify "The file $path does not exist."
  exit 1
fi
# When Sublime Text is not open, subl starts it as a child. Herdr stops the processes
# of an action when the action ends. Under setsid, Sublime Text does not start. So
# start subl as a systemd user unit. subl exits at once, and systemd then stops the
# processes of the unit: KillMode=process keeps Sublime Text. AGENT_TABS_LAUNCHER
# replaces systemd-run, for the tests.
"${AGENT_TABS_LAUNCHER:-systemd-run}" --user --collect --quiet -p KillMode=process \
  "${AGENT_TABS_EDITOR:-subl}" "$path${line:+:$line}" </dev/null
