#!/usr/bin/env bash
# Action board: pick an Obsidian Kanban board, then open an orchestrator claude for it.
#
#   board.sh open                action: open the board popup
#   board.sh prompt              popup: list the boards, read one key, start the worker
#   board.sh worker BOARD        worker: start the orchestrator in the workspace "BOARD orchestrator"
#                                of the user, send /board-orchestrator, and focus it
#   board.sh stop                action: stop an orchestrator
#   board.sh stop-prompt         popup: list the running orchestrators, read one key, stop it
#   board.sh stop-board BOARD    background: stop the orchestrator of BOARD (see stop_board)
#
# A board is a file Boards/*.md in the vault that has the line "kanban-plugin: board".
# The orchestrator is a claude in the workspace "BOARD orchestrator" of the session of
# the user. Its workers run in the hidden Herdr session BOARD_SESSION, and their views
# open in that same workspace. Claude starts in the vault folder with effort high. After
# a Herdr restart, Herdr resumes the orchestrator claude in its pane.
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"
use_user_session

# Print the prompt "Board: [1] a  [2] b: " for the boards $@, read one key, and print the
# board of the key. Return 1 on Esc, ctrl+c and at the end of the input.
pick_board() {
  local list="" i key
  keys_hint
  for ((i = 1; i <= $#; i++)); do
    list+="[$i] ${!i}  "
  done
  while true; do
    printf 'Board: %s: ' "$list" >&2
    IFS= read -r -s -n 1 key || return 1
    if [ "$key" = $'\e' ]; then
      if ! read_escape; then
        printf '\n' >&2
        return 1
      fi
      printf '\n' >&2
      continue
    fi
    printf '%s\n' "$key" >&2
    case "$key" in
      [1-9])
        if [ "$key" -le "$#" ]; then
          printf '%s\n' "${!key}"
          return 0
        fi
        ;;
      $'\003') return 1 ;;
    esac
  done
}

# Return 0 when the pane $1 of the session of the user is at a shell prompt.
at_shell() {
  local exe
  exe=$("$H" pane process-info --pane "$1" 2>/dev/null |
    jq -r '.result.process_info.foreground_processes[0] | .argv0 // .argv[0] // ""' 2>/dev/null) || return 1
  exe=${exe##*/}
  case "${exe#-}" in bash | zsh | sh | fish | dash) return 0 ;; *) return 1 ;; esac
}

# Stop the orchestrator of board $1: close its workspace "$1 orchestrator". The close
# stops claude: no /exit is necessary. The next open starts a new claude session. First
# check that each pane of the workspace is the orchestrator, a worker view or a shell.
# On a refusal, change nothing. The workers in "$1 workers" of the hidden session go on.
# The lock of board_start_lock keeps an open of the board from starting an orchestrator
# during the stop. Return 1 with a notification on a refusal and when the close fails.
stop_board() {
  local board=$1 orch ws panes p reason=""
  exec 7>>"$(board_start_lock "$board")"
  flock 7
  if ! ws=$(board_workspace_id "$board"); then
    toast "Could not read the workspace $board orchestrator. Nothing changed."
    return 1
  fi
  if ! orch=$(orchestrator_pane "$board"); then
    toast "No orchestrator runs for the board $board."
    return 1
  fi
  if ! panes=$("$H" pane list --workspace "$ws" 2>/dev/null); then
    toast "Could not read the workspace $board orchestrator. Nothing changed."
    return 1
  fi
  while IFS= read -r p; do
    [ "$p" = "$orch" ] || runs_attach "$p" "" || at_shell "$p" ||
      reason="The workspace $board orchestrator has a pane that runs a program ($p)."
  done < <(jq -r '.result.panes[]?.pane_id // empty' <<<"$panes" 2>/dev/null)
  if [ -n "$reason" ]; then
    toast "$reason Nothing changed. Close that pane, then stop again."
    return 1
  fi
  if ! "$H" workspace close "$ws" >/dev/null 2>&1; then
    toast "Could not stop the orchestrator of the board $board. Nothing changed."
    return 1
  fi
  toast "Stopped the orchestrator of the board $board."
}

case "${1:-}" in
  open)
    if [ -z "${HERDR_WORKSPACE_ID:-}" ] || [ -z "${HERDR_PANE_ID:-}" ]; then
      toast "No pane has focus. Focus a pane, then try again."
      exit 1
    fi
    "$H" plugin pane open --plugin "$HERDR_PLUGIN_ID" --entrypoint board-prompt >/dev/null
    ;;
  prompt)
    if ! vault=$(vault_path); then
      toast "No vault path. Set OBSIDIAN_VAULT_PATH."
      exit 1
    fi
    boards=()
    for file in "$vault"/Boards/*.md; do
      if [ -f "$file" ] && grep -qx 'kanban-plugin: board' "$file"; then
        boards+=("$(basename "$file" .md)")
      fi
    done
    if [ "${#boards[@]}" -eq 0 ]; then
      toast "No board in $vault/Boards."
      exit 1
    fi
    board=$(pick_board "${boards[@]}") || exit 0
    log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/board.log"
    detach bash "$here/board.sh" worker "$board" \
      </dev/null >>"$log" 2>&1
    ;;
  worker)
    board="$2"
    # One orchestrator for each board: focus the one that runs.
    focus_running() {
      local orch ws
      orch=$(orchestrator_pane "$board") || return 1
      # Start the listener of the worker counts again when it stopped.
      detach "$here/dispatch.sh" count-watch >/dev/null 2>&1 </dev/null 7>&-
      # A manual fallback after a restart: open the views that are missing.
      detach bash "$here/dispatch.sh" views-restore </dev/null >>"${HERDR_PLUGIN_STATE_DIR:-/tmp}/board.log" 2>&1 7>&-
      ws=$(board_workspace_id "$board") || ws=""
      [ -z "$ws" ] || "$H" workspace focus "$ws" >/dev/null 2>&1 || true
      "$H" agent focus "$orch" >/dev/null 2>&1 || true
    }
    focus_running && exit 0
    if ! vault=$(vault_path); then
      toast "No vault path. Set OBSIDIAN_VAULT_PATH."
      exit 1
    fi
    # React at once: claude takes seconds to start.
    toast "Starting the orchestrator of the board $board."
    # One start or stop of the orchestrator of the board at a time. An open that waited
    # for another open finds the orchestrator of that open.
    exec 7>>"$(board_start_lock "$board")"
    flock 7
    focus_running && exit 0
    # No fallback workspace: never start an orchestrator in another workspace.
    if ! new_pane=$(WS_NO_START=1 workspace_pane "$board orchestrator" "$vault" --focus "" ""); then
      toast "Could not open the workspace $board orchestrator."
      exit 1
    fi
    # Keep the worker counts of the workspace up to date. Only after the lookups work:
    # the listener retries a failed lookup for as long as the hidden session runs.
    detach "$here/dispatch.sh" count-watch >/dev/null 2>&1 </dev/null 7>&-
    # Herdr names the tab with a number: name it after its claude.
    tab=$("$H" pane get "$new_pane" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null) || tab=""
    [ -z "$tab" ] || "$H" tab rename "$tab" orchestrator >/dev/null 2>&1 || true
    # A start can wait at a question (the trust of the folder): the user answers it in
    # the pane.
    started=1
    start_claude "$new_pane" high || started=""
    if [ -z "$started" ] &&
      ! "$H" agent wait "$new_pane" --until idle --until "done" --timeout 600000 >/dev/null 2>&1; then
      toast "Claude did not start in $new_pane."
      exit 1
    fi
    # /rename first: the session title then gives the agent name, and the name lasts.
    # The orchestrator name is a slug: orchestrator_pane finds the claude by that name.
    name=$(agent_slug "$board-orchestrator")
    "$H" agent prompt "$new_pane" "/rename $name" >/dev/null || true
    if ! "$H" agent prompt "$new_pane" "/board-orchestrator $board" >/dev/null; then
      toast "Claude in $new_pane did not get the board command."
      exit 1
    fi
    rename_agent "$new_pane" "$name"
    ;;
  stop)
    mapfile -t boards < <(orchestrator_boards || true)
    case "${#boards[@]}" in
      0) toast "No board orchestrator runs." ;;
      1)
        toast "Stopping the orchestrator of the board ${boards[0]}."
        detach bash "$here/board.sh" stop-board "${boards[0]}" </dev/null >>"${HERDR_PLUGIN_STATE_DIR:-/tmp}/board.log" 2>&1
        ;;
      *) "$H" plugin pane open --plugin "$HERDR_PLUGIN_ID" --entrypoint board-stop-prompt >/dev/null ;;
    esac
    ;;
  stop-prompt)
    mapfile -t boards < <(orchestrator_boards || true)
    [ "${#boards[@]}" -gt 0 ] || exit 0
    board=$(pick_board "${boards[@]}") || exit 0
    # The stop takes seconds: close the popup at once.
    toast "Stopping the orchestrator of the board $board."
    detach bash "$here/board.sh" stop-board "$board" </dev/null >>"${HERDR_PLUGIN_STATE_DIR:-/tmp}/board.log" 2>&1
    ;;
  stop-board)
    stop_board "$2"
    ;;
  *)
    printf 'usage: board.sh open|prompt|worker BOARD|stop|stop-prompt|stop-board BOARD\n' >&2
    exit 2
    ;;
esac
