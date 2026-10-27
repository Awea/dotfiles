#!/usr/bin/env bash
# Claude Code SessionStart hook: keep the Herdr agent name of claude equal to its
# session title, also after /rename.
#
#   sync-name.sh start        hook: start one background loop for the current pane
#   sync-name.sh loop PANE [LOCK]
#                             loop: copy the title to the agent name until claude exits
#
# Make links the script as ~/.claude/hooks/herdr-agent-name.sh.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

case "${1:-}" in
  start)
    # Claude Code sends the hook input on stdin. The loop does not use it.
    cat >/dev/null || true
    [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0
    # One loop for each pane: a second session in the same pane uses the running loop.
    lock="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/herdr-agent-name-${HERDR_PANE_ID//:/_}.lock"
    log="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/awea.agent-tabs/sync-name.log"
    mkdir -p "$(dirname "$log")"
    if command -v flock >/dev/null; then
      detach flock -n "$lock" bash "$here/sync-name.sh" loop "$HERDR_PANE_ID" </dev/null >>"$log" 2>&1
    else
      # macOS has no flock. The loop takes the lock folder itself.
      detach bash "$here/sync-name.sh" loop "$HERDR_PANE_ID" "$lock.d" </dev/null >>"$log" 2>&1
    fi
    ;;
  loop)
    # LOCK is a folder: mkdir makes it for one loop only. The folder keeps the PID of
    # the loop. A loop that stopped without cleanup leaves the folder: take it then.
    lock="${3:-}"
    if [ -n "$lock" ] && ! mkdir "$lock" 2>/dev/null; then
      pid=$(cat "$lock/pid" 2>/dev/null) || pid=""
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        exit 0
      fi
    fi
    if [ -n "$lock" ]; then
      printf '%s\n' "$$" >"$lock/pid"
      trap 'rm -rf "$lock"' EXIT
    fi
    sync_agent_name "$2"
    ;;
  *)
    printf 'usage: sync-name.sh start|loop PANE [LOCK]\n' >&2
    exit 2
    ;;
esac
