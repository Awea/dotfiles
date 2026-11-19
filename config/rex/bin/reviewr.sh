#!/usr/bin/env bash
# ctrl+b d in Renux: run herdr-reviewr on DIR in this Rex pane. Its herdr calls go to
# herdr-shim, with the session, window and block of this pane as the Herdr ids.
#
#   reviewr.sh DIR [BASE]
#
# With BASE: the branch scope on BASE (config/rex/reviewr-branch, --base), as
# herdr-app/bin/agent-tabs.sh reviewr does.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
here=$(dirname "$(readlink -f "$0")")

# reviewr_bin: herdr-reviewr from PATH, else from the Herdr 0.9.5 plugin install.
reviewr_bin() {
  local f
  if [ -n "${REVIEWR_BIN:-}" ]; then printf '%s\n' "$REVIEWR_BIN"; return; fi
  if command -v herdr-reviewr >/dev/null 2>&1; then command -v herdr-reviewr; return; fi
  for f in "$HOME"/.config/herdr/plugins/github/persiyanov.reviewr-*/bin/herdr-reviewr; do
    [ -x "$f" ] && printf '%s\n' "$f" && return
  done
  return 1
}

if ! bin=$(reviewr_bin); then
  printf 'reviewr.sh: herdr-reviewr is not installed.\n' >&2
  exec "${SHELL:-sh}"
fi
config=reviewr
flags=()
if [ -n "${2:-}" ]; then
  config=reviewr-branch
  flags=(--base "$2")
fi
window=$(rex api call session.list_blocks "$(jq -cn --arg s "${REX_SESSION:-}" '{session_id: $s}')" |
  jq -r --arg b "${REX_BLOCK:-}" '.blocks[] | select(.block_id == $b) | .window_id') || window=
HERDR_BIN_PATH="$here/herdr-shim" \
  HERDR_WORKSPACE_ID=${REX_SESSION:-} \
  HERDR_TAB_ID=$window \
  HERDR_PANE_ID=${REX_BLOCK:-} \
  HERDR_PLUGIN_CONFIG_DIR="$(cd "$here/../$config" && pwd)" \
  exec "$bin" ${flags[@]+"${flags[@]}"} "${1:?usage: reviewr.sh DIR [BASE]}"
