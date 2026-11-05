#!/usr/bin/env bash
# Claude Code SessionStart hook: keep the Herdr agent name of claude equal to its
# session title, also after /rename.
#
#   sync-name.sh start        hook: make sure that one listener runs for the Herdr
#                             session of the current pane
#   sync-name.sh listen PANE  listener: rename each claude of the session when its
#                             title changes. Without events, poll PANE as loop does.
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
    # The listener needs flock and nc. Without them, poll the pane as before.
    if command -v flock >/dev/null && command -v "${DISPATCH_NC:-nc}" >/dev/null; then
      detach bash "$here/sync-name.sh" listen "$HERDR_PANE_ID" </dev/null >>"$log" 2>&1
    elif command -v flock >/dev/null; then
      detach flock -n "$lock" bash "$here/sync-name.sh" loop "$HERDR_PANE_ID" </dev/null >>"$log" 2>&1
    else
      # macOS has no flock. The loop takes the lock folder itself.
      detach bash "$here/sync-name.sh" loop "$HERDR_PANE_ID" "$lock.d" </dev/null >>"$log" 2>&1
    fi
    ;;
  listen)
    # One listener for each Herdr session: pane.updated has no pane filter, so one
    # listener gets the title changes of all claudes. A second listener exits at once.
    pane=$2
    dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    exec 8>>"$(name_listener_file lock)"
    # After a restart for new code, the old listener can still hold the lock for a
    # moment: wait for it.
    if [ -n "${AGENT_TABS_NAME_RESTART:-}" ]; then
      unset AGENT_TABS_NAME_RESTART
      flock -w 5 8 || exit 0
    else
      flock -n 8 || exit 0
    fi
    names=$(name_listener_file names)
    # The listener runs for a long time: it must not keep old code after a git pull or
    # an edit. A file that is not older than this stamp makes a restart, as in
    # dispatch.sh count-watch.
    stamp=$(name_listener_file stamp)
    touch "$stamp"
    ev_dir="" nc_pid=""
    # Stop nc and remove its fifos, at each exit and before each new connection.
    close_events() {
      [ -z "$nc_pid" ] || kill "$nc_pid" 2>/dev/null || true
      exec 6<&- 7>&-
      [ -z "$nc_pid" ] || wait "$nc_pid" 2>/dev/null || true
      nc_pid=""
      [ -z "$ev_dir" ] || rm -rf "$ev_dir"
      ev_dir=""
    }
    trap close_events EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # A write to an nc that cannot connect must not stop the listener.
    trap '' PIPE
    request=$(jq -cn '{id: "agent-name", method: "events.subscribe",
      params: {subscriptions: [{type: "pane.updated"}, {type: "pane.agent_detected"}]}}')
    ever=""
    while :; do
      sock=$("$H" session list --json 2>/dev/null | jq -r --arg s "$PANE_SESSION" \
        '[.sessions[]? | select(.name == $s and .running == true) | .socket_path // empty][0] // empty' 2>/dev/null) || sock=""
      [ -n "$sock" ] || exit 0
      # 2 fifos, one for each direction. nc runs as a plain background job: bash 3.2
      # (macOS) sets no $! for a process substitution. nc must not keep the lock.
      ev_dir=$(mktemp -d "$dir/herdr-agent-name.XXXXXX")
      mkfifo "$ev_dir/in" "$ev_dir/out"
      "${DISPATCH_NC:-nc}" -U "$sock" <"$ev_dir/in" >"$ev_dir/out" 2>/dev/null 8>&- &
      nc_pid=$!
      # Each open waits for the other end: nc opens its stdin first, then its stdout.
      exec 7>"$ev_dir/in" 6<"$ev_dir/out"
      (printf '%s\n' "$request" >&7) 2>/dev/null || true
      started="" failed=""
      while :; do
        # Wait 5 seconds for the reply. After it, an event can come at any time.
        if [ -n "$started" ]; then
          IFS= read -r line <&6 || break
        else
          IFS= read -r -t 5 line <&6 || break
        fi
        if ! [ "$stamp" -nt "$here/sync-name.sh" ] || ! [ "$stamp" -nt "$here/lib.sh" ]; then
          close_events
          exec 8>&-
          # The new stamp must be in a later second than the change, else the new
          # listener restarts again.
          sleep 1
          AGENT_TABS_NAME_RESTART=1 exec "$BASH" "$here/sync-name.sh" listen "$pane"
        fi
        # A tab is white space for read: an empty first field would go. Use \x1f.
        IFS=$'\x1f' read -r event id kind released < <(jq -r '[.event // (if .error then "error" else "" end),
          (.data.pane.pane_id // .data.pane_id // .result.type // ""), (.data.pane.agent // .data.agent // ""),
          (.data.released // false | tostring)] | join("\u001f")' <<<"$line" 2>/dev/null) || continue
        case "$event" in
          "")
            [ "$id" = subscription_started ] || continue
            started=1 ever=1
            # A claude can change its title before the subscription starts: sync each
            # claude of the session once.
            while IFS= read -r id; do
              [ -z "$id" ] || sync_pane_name "$id" "$names"
            done < <("$H" agent list 2>/dev/null |
              jq -r '.result.agents[]? | select(.agent == "claude") | .pane_id' 2>/dev/null)
            ;;
          error)
            failed=1
            break
            ;;
          pane_updated | pane.updated)
            [ "$kind" != claude ] || sync_pane_name "$id" "$names"
            ;;
          pane_agent_detected | pane.agent_detected)
            if [ "$released" = true ]; then
              remember_agent_name "$names" "$id" ""
            elif [ "$kind" = claude ]; then
              sync_pane_name "$id" "$names"
            fi
            ;;
        esac
      done
      close_events
      if [ -z "$ever" ]; then
        # The events do not work here: poll the pane of the hook, as before. Give the
        # session lock free, so that the hook of the next claude tries the events again.
        exec 8>&-
        exec 9>>"$dir/herdr-agent-name-${pane//:/_}.lock"
        flock -n 9 || exit 0
        sync_agent_name "$pane"
        exit 0
      fi
      # A refused subscription or a lost connection: connect again after a pause. When
      # the session stops, the socket is gone and the listener exits at the top.
      [ -n "$started" ] || [ -n "$failed" ] || exit 1
      sleep 1
    done
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
    printf 'usage: sync-name.sh start|listen PANE|loop PANE [LOCK]\n' >&2
    exit 2
    ;;
esac
