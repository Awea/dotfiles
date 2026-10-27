#!/usr/bin/env bash
# Action new-tab: ask for a prompt, then start claude with it in a new tab.
#
#   new-agent-tab.sh open                   action: open the prompt popup
#   new-agent-tab.sh prompt                 popup: ask for the prompt, start the worker
#   new-agent-tab.sh worker PANE WS PROMPT [EFFORT] [--focus|--no-focus]
#                                           worker: open the tab, send the prompt
#
# Claude starts in the folder of the pane. In a linked git worktree, claude starts in
# the root of the main worktree of the repo.
# The tab opens in the background (--no-focus, the default) or gets the focus.
# With a prompt, the agent then gets the session title of claude, or the start of the
# prompt. Without a prompt, a clean claude tab opens.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

case "${1:-}" in
  open)
    if [ -z "${HERDR_WORKSPACE_ID:-}" ] || [ -z "${HERDR_PANE_ID:-}" ]; then
      notify "No pane has focus. Focus a pane, then try again."
      exit 1
    fi
    "$H" plugin pane open --plugin "$HERDR_PLUGIN_ID" --entrypoint new-tab-prompt \
      --env "AGENT_TABS_PANE=$HERDR_PANE_ID" --env "AGENT_TABS_WORKSPACE=$HERDR_WORKSPACE_ID" >/dev/null
    ;;
  prompt)
    keys_hint
    prompt=$(read_line "Prompt for the new claude (Enter for a clean tab): ") || exit 0
    effort=$(read_effort) || exit 0
    focus=$(read_focus) || exit 0
    log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/new-tab.log"
    detach bash "$here/new-agent-tab.sh" worker "$AGENT_TABS_PANE" "$AGENT_TABS_WORKSPACE" "$prompt" "$effort" "$focus" \
      </dev/null >>"$log" 2>&1
    ;;
  worker)
    pane="$2" workspace="$3" prompt="$4" effort="${5:-}" focus="${6:---no-focus}"
    cwd=$(main_worktree "$(pane_cwd "$pane")")
    if ! new_pane=$(open_claude_tab "$workspace" "$cwd" "$focus" "$effort"); then
      notify "Claude did not start in the new tab."
      exit 1
    fi
    if [ -n "$prompt" ] && ! "$H" agent prompt "$new_pane" "$prompt" >/dev/null; then
      notify "Claude in $new_pane did not get the prompt."
      exit 1
    fi
    if [ -n "$prompt" ]; then
      name_agent "$new_pane" "$prompt"
    fi
    ;;
  *)
    printf 'usage: new-agent-tab.sh open|prompt|worker PANE WS PROMPT [EFFORT] [--focus|--no-focus]\n' >&2
    exit 2
    ;;
esac
