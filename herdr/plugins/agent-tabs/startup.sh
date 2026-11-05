#!/usr/bin/env bash
# The startup hook of the plugin (herdr-plugin.toml, [[startup]]): Herdr runs it when it
# starts, also after a restart that restored the sessions. Return at once. In the
# background, rebuild the views of the board workers (they come back as bare shells),
# then tell each orchestrator that its background commands stopped (restart-notice, which
# returns at once), then make sure that the listener of the worker counts runs. The restore waits for the
# hidden session and the resumed agents; count-watch needs the hidden session, so it
# comes last.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"
log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/board.log"
# shellcheck disable=SC2016 # The inner bash expands $1.
detach bash -c '"$1/dispatch.sh" views-restore --wait; "$1/dispatch.sh" restart-notice; "$1/dispatch.sh" count-watch' _ "$here" \
  </dev/null >>"$log" 2>&1
