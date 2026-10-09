#!/usr/bin/env bash
# Action handoff: run /handoff in the focused claude, then continue in a new tab.
#
#   handoff.sh open                     action: check the focused agent, open the popup
#   handoff.sh prompt                   popup: ask for the focus, start the worker
#   handoff.sh worker PANE WS FOCUS [EFFORT] [--focus|--no-focus]
#                                       worker: run /handoff, then open the new tab
#
# FOCUS is the focus of the next session. The last argument tells if the new tab gets
# the focus. The default is --no-focus.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

case "${1:-}" in
  open)
    pane="${HERDR_PANE_ID:-}"
    status=$("$H" agent get "$pane" 2>/dev/null |
      jq -r 'select(.result.agent.agent == "claude") | .result.agent.agent_status') || status=""
    if [ "$status" != "idle" ] && [ "$status" != "done" ]; then
      notify "Focus an idle claude agent, then try again."
      exit 1
    fi
    "$H" plugin pane open --plugin "$HERDR_PLUGIN_ID" --entrypoint handoff-prompt \
      --env "AGENT_TABS_PANE=$pane" --env "AGENT_TABS_WORKSPACE=$HERDR_WORKSPACE_ID" >/dev/null
    ;;
  prompt)
    keys_hint
    focus=$(read_line "Focus for the next session (Enter to skip): ") || exit 0
    effort=$(read_effort) || exit 0
    tab_focus=$(read_focus) || exit 0
    log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/handoff.log"
    setsid -f bash "$here/handoff.sh" worker "$AGENT_TABS_PANE" "$AGENT_TABS_WORKSPACE" "$focus" "$effort" "$tab_focus" \
      </dev/null >>"$log" 2>&1
    ;;
  worker)
    pane="$2" workspace="$3" focus="$4" effort="${5:-}" tab_focus="${6:---no-focus}"
    doc="${TMPDIR:-/tmp}/herdr-handoff-$(date +%Y%m%d-%H%M%S)-$$.md"
    # The title of the new session: the focus, else the source title with "handoff".
    # Without it, claude makes a title from the first prompt, the same for each handoff.
    title="$focus"
    if [ -z "$title" ]; then
      title=$("$H" agent get "$pane" 2>/dev/null | jq -r '.result.agent.terminal_title_stripped // empty') || title=""
      case "$title" in "" | claude | "Claude Code") title="" ;; *) title="$title handoff" ;; esac
    fi
    if ! "$H" agent prompt "$pane" "/handoff ${focus:+$focus. }Save the handoff document to $doc" \
      --wait --until idle --until "done" --timeout 900000 >/dev/null; then
      notify "The /handoff in $pane did not end in 15 minutes."
      exit 1
    fi
    if [ ! -s "$doc" ]; then
      notify "The agent in $pane did not write $doc."
      exit 1
    fi
    if ! new_pane=$(open_claude_tab "$workspace" "$(pane_cwd "$pane")" "$tab_focus" "$effort"); then
      notify "Claude did not start in the new tab. The handoff document is $doc."
      exit 1
    fi
    # /rename does not make claude work, so do not wait for it.
    [ -z "$title" ] || "$H" agent prompt "$new_pane" "/rename $title" >/dev/null || true
    if ! "$H" agent prompt "$new_pane" "Read the handoff document at $doc, then continue the work." >/dev/null; then
      notify "Claude in $new_pane did not get the prompt. The handoff document is $doc."
      exit 1
    fi
    name_agent "$new_pane" "$focus"
    ;;
  *)
    printf 'usage: handoff.sh open|prompt|worker PANE WS FOCUS [EFFORT] [--focus|--no-focus]\n' >&2
    exit 2
    ;;
esac
