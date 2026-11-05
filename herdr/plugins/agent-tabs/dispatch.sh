#!/usr/bin/env bash
# Tool of the board orchestrator: run a worker claude in a new tab, wait for its report.
# The workers run in the hidden Herdr session DISPATCH_SESSION (board-workers by
# default), out of the sidebar of the user. A worker pane ID is an ID of that session.
# Notifications and view tabs are in the session of the user.
#
#   dispatch.sh policy CWD
#       Print the push policy of the project at CWD: deny, ask or allow when
#       .claude/settings.json or .claude/settings.local.json has a Bash(git push...) rule
#       in that list of permissions (in this order), else missing.
#   dispatch.sh policy-set CWD allow|ask
#       Add the push rules (git push, gh pr create|comment|edit|ready|close,
#       gh issue create|comment|edit) to permissions.allow or permissions.ask of
#       CWD/.claude/settings.local.json, and the merge rules (gh pr merge, tea pr merge,
#       tea pulls merge, mcp__forgejo__merge_pull_request) to permissions.deny: a worker
#       never merges. Remove the old wide forge rules (gh pr merge|review, gh release,
#       gh repo create, gh gist, gh api -X|--method) from allow and ask. Print the policy.
#       The host of the origin remote gives the forge: github.com is GitHub, any other
#       host or no remote is Forgejo. For Forgejo, the push rules are git push and
#       mcp__forgejo__ create|update_pull_request, create|update_issue,
#       create|edit_issue_comment, issue_state_change; the merge rules are tea pr|pulls
#       merge and mcp__forgejo__merge_pull_request; the gh rules that policy-set wrote
#       (the gh push rules, the old wide rules and gh pr merge) go from allow, ask and
#       deny. Other gh rules stay.
#   dispatch.sh start task|auto CWD NAME PROMPT_FILE
#       Exit 2 with no Herdr call in a pane of the hidden session. Start the hidden session when it does not run, with the environment of the
#       default Herdr server (DISPATCH_SERVER_ENVIRON, else /proc/PID/environ), and clear
#       the views file; log in the state folder, server.log. Exit 1 and start no worker
#       when it does not answer in DISPATCH_SESSION_WAIT seconds (10 by default).
#       Open a tab at CWD in the hidden session, in the workers workspace of the board:
#       the label of $HERDR_WORKSPACE_ID (the orchestrator workspace) with " orchestrator"
#       at the end replaced by " workers", or with " workers" added. Create the workspace
#       when it is missing. Exit 1 when the orchestrator workspace lookup fails. When
#       claude does not start or does not get the prompt, print the pane ID and exit 1. Start claude, send the
#       prompt of PROMPT_FILE plus a footer, and name the agent from NAME.
#       Print the pane ID, then the report path. Add the line "PANE<tab>MODE<tab>BOARD<tab>REPORT"
#       to the workers file in the state folder (workers-S), in place of an older line
#       of PANE. BOARD is the workers workspace label without " workers".
#       task: CWD must have a push policy.
#       auto: the worker runs with only the user settings and CWD/.claude/settings.readonly.json
#       (its permissions.allow must have a rule), in dontAsk mode.
#   dispatch.sh wait PANE REPORT [STATUS SEQ]
#       Wait until REPORT exists and is not empty (exit 0), or until Herdr finds no
#       agent in PANE (exit 1), or until the worker needs the user (exit 3): the agent
#       status is blocked, or idle or done with no report two checks in a row (with the
#       same seq). When the worker screen shows a background job ("N shell" on the
#       bottom bar, "still running" on the last done line, or a background subagent
#       line), the need is idle-job, with the same rules as idle.
#       On exit 3, print blocked, idle or idle-job and the seq ("blocked 7"): the
#       state_change_seq for blocked, the completion_seq for idle and idle-job (else the
#       state_change_seq).
#       With STATUS SEQ (the words of an earlier exit 3), do not exit 3 for that same need:
#       exit 3 again only for another status or seq. When Herdr or the call gives no seq,
#       exit 3 again only after another status. A report always wins. On exit 1 and
#       exit 3, show a Herdr notification, but not for idle-job: the orchestrator reads
#       the last message and decides.
#       Check every DISPATCH_POLL seconds (30 by default).
#   dispatch.sh last PANE
#       Print the last message of the worker in PANE: the text parts of the last
#       assistant line with text in its transcript (the claude session ID of the agent,
#       under ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/), cut to the last 3000
#       characters. With no session ID, transcript or text, print the last 40 lines of
#       the screen. Exit 1 when Herdr finds no agent in PANE.
#   dispatch.sh watch PANE REPORT [STATUS SEQ]
#       Wait until REPORT changes after the call: its content or its mtime (exit 0).
#       Exit 1 when Herdr finds no agent in PANE 3 times in a row and REPORT did not
#       change, with no notification. Exit 3 with the rules of wait when the worker
#       needs the orchestrator: blocked (with a notification), or idle or idle-job (no
#       notification) with a seq other than the baseline: SEQ, else the completion_seq
#       (else the state_change_seq) at the first check. Print the need and the seq as
#       wait does. With STATUS SEQ, do not exit 3 for that same need. A report change
#       always wins. Check every DISPATCH_POLL seconds (30 by default).
#   dispatch.sh remind PANE REPORT
#       Tell an idle worker to write its report again to REPORT (an agent prompt in the
#       hidden session), exit 0. Wait with no time limit while the user focuses the view
#       pane of PANE. Exit 1 when Herdr finds no agent in PANE, or when the worker is
#       not idle or done (it works or waits at a prompt).
#   dispatch.sh answer PANE FILE
#       Send the words of the user in FILE to the worker (an agent prompt in the hidden
#       session), after the line "The user answers through the orchestrator:" and a
#       blank line, exit 0. Wait with no time limit while the user focuses the view pane
#       of PANE, and while the worker is not idle or done: never type in a permission
#       prompt. Exit 2 when FILE is missing or empty. Exit 1 when Herdr finds no agent
#       in PANE, or when the prompt fails.
#   dispatch.sh notify PANE waits|stop|refused
#       Show a Herdr notification that the worker in PANE needs the user, with a fixed
#       body for that kind. Exit 2 for another kind.
#   dispatch.sh show PANE [need]
#       Open a view tab of the worker with no focus. For a caller in the session of the
#       user (the orchestrator), open it in $HERDR_WORKSPACE_ID, else exit 2. For a caller
#       in the hidden session, open it in the workspace "BOARD orchestrator" of the user
#       (BOARD of the workers file). With no BOARD, exit 2. When that workspace is gone,
#       exit 1 and create no workspace. Label the tab with the agent name (else "worker"), and run `herdr --session S agent attach PANE` in
#       it. Print the view pane ID. When a view of PANE still exists and runs the attach
#       of PANE, print it and open nothing. Exit 1 when the worker is gone, or when the
#       attach does not run after DISPATCH_ATTACH_WAIT seconds (3 by default). The views file in the state folder
#       (views-S) keeps one line "PANE VIEW AGENT STATE" for each view. Report the view
#       pane to Herdr as an agent only when it is red or when a reviewr pane is open in
#       its tab (else release it): reviewr sends its notes only to an agent, and the
#       text goes through the view to the worker. The agent has the state of the worker
#       (working, idle, blocked), the project of the worker as its label, and the agent
#       name of the worker when that name is free in the session of the user. With need,
#       report it blocked: Herdr shows the view and the orchestrator workspace red, and the
#       orchestrator does not stop. wait, watch and count-watch copy each status of the
#       worker to the view; a red view stays red until the worker works, or ends a new
#       turn (a new completion seq). count-watch releases the view of a worker that is
#       gone.
#   dispatch.sh views-sync
#       The hook of pane.closed and pane.exited: apply the rule of show to each view in
#       the views file. A view that is no red and has no reviewr in its tab is released.
#   dispatch.sh views-restore [--wait]
#       Rebuild the views after a restart of Herdr: the view panes come back as bare
#       shells, the workers come back with their pane IDs. For each worker in the workers
#       file whose pane runs a claude: find the workspace "BOARD orchestrator" of the user
#       (skip a board with none). In it, close each tab that has no orchestrator and
#       whose panes all show only a login shell. Then, for a worker with no valid view,
#       run show with no focus. A second run changes nothing. A lock keeps 2 runs apart.
#       With --wait, repeat every DISPATCH_RESTORE_POLL seconds (5) up to
#       DISPATCH_RESTORE_WAIT seconds (180) until the hidden session and all workers are
#       back. Log to stderr; always exit 0.
#   dispatch.sh restart-notice
#       Only startup.sh runs it, after views-restore. Return at once. For each running
#       orchestrator of the user, a detached call waits until it is idle or done
#       (DISPATCH_NOTICE_TIMEOUT_MS, 300000 by default), then sends one prompt: its
#       background wait and watch commands stopped with Herdr; run workers BOARD and
#       handle each worker as in rules 6 and 7. A call that fails logs one line to
#       stderr and sends nothing. Exit 0 at once in the hidden session.
#   dispatch.sh sync PANE
#       The same for the view of the worker pane PANE (reviewr.sh runs it, detached).
#   dispatch.sh workers BOARD
#       Print one JSON line for each agent in the workspace "BOARD workers" of the hidden
#       session: pane, name, status, seq (the completion_seq, else the state_change_seq,
#       as a string, else null), mode and report (from the workers file; with no line,
#       mode null and report the newest NAME-<date>-*.md in the state folder, else
#       null), report_exists, first_line, report_mtime (ISO), view (the view pane when
#       it runs the attach of the pane, else null), job (idle or done, and the screen
#       shows a background job), live (working, or job) and waits (blocked, or not live
#       and the report is not RESULT: DONE or STATUS: OK). Exit 0 with no output when the
#       workspace does not exist. Exit 1 when the hidden session does not run.
#   dispatch.sh report PATH
#       Print a summary of the report PATH: the first line, the ## Result section, the
#       ## Vault changes section, the REFUSED: lines of other sections, then the line
#       "full report: PATH (N lines)". With no ## Result section, print the first 40
#       lines in place of the sections. Cut each section at 60 lines, with a line that
#       gives the number of cut lines. Exit 2 when PATH is not a file.
#   dispatch.sh note-add NOTE BOARD LINE TITLE
#       Copy the context lines of the card at line LINE of <vault>/Boards/BOARD.md to the
#       task note NOTE (relative to the vault), under ## Notes, then ### YYYY-MM-DD, from
#       the board (today). Remove one tab at the start of each line, and put each heading
#       3 levels lower. Add ## Notes at the end of the note when it has none. When the
#       note has an updated: field, set it to today. Print "note-add: NOTE YYYY-MM-DD".
#       The board does not change. Exit 1 and change nothing when LINE is not the title
#       line of the card TITLE (the text between ** and **, the title field of
#       board-scan.sh), when the card has no context line, or when it has task links and
#       none is NOTE. Exit 2 with no NOTE, BOARD, LINE number or TITLE.
#   dispatch.sh log BOARD FILE
#       Add the line "- HH:MM TEXT" under ## Log of the vault note
#       "Dev Logs/YYYY-MM-DD - BOARD (board orchestrator).md". TEXT is the text of FILE,
#       with a space for each line end: a card title on the command line can run as a
#       command. Create the note when it
#       does not exist. When Daily/YYYY-MM-DD.md exists and has no link to the note, add
#       a link at the end of its ## Work section, or at the end of the note when it has
#       no such section. Never create a daily note. Exit 2 with no BOARD, or when FILE is
#       missing or empty. Exit 1 when there is no vault path.
#   dispatch.sh inbox-clear _inbox/NAME.md
#       Delete a phone message of the vault inbox after the orchestrator made a card of
#       it. The vault MCP tools cannot delete a file. Delete only a *.md file directly in
#       _inbox, never a dot file. Exit 2 for another path, exit 1 when there is no vault
#       path or the file is gone (the orchestrator of another board cleared it).
#   dispatch.sh count-watch
#       Keep the tokens "workers" and "working" of each workspace "BOARD orchestrator"
#       of the user up to date, with no poll. Listen to the Herdr events of the hidden
#       session on its socket (nc -U, or DISPATCH_NC): the status changes of each claude
#       in a workspace "BOARD workers", and the pane events (created, closed, exited,
#       agent detected). A status change of a worker shows the counts of its board again.
#       At the subscription, count each board with a workspace "BOARD workers" of the
#       hidden session or "BOARD orchestrator" of the user. A pane
#       event makes the listener subscribe again with the new panes: a status event needs
#       a pane ID. Exit 0 at once when another listener of the session runs (a lock in
#       the state folder), and when the session stops. Exit 1 when the socket gives no
#       reply. The mode start and board.sh worker run it in the background after they
#       make sure that the session runs. A failed lookup or an error reply while the session
#       runs gives a new try after 1 second.
#   dispatch.sh close PANE [wait]
#       Wait until the worker is idle or done (DISPATCH_CLOSE_WAIT seconds, 90 by
#       default), print its claude session ID (an empty line when Herdr gives none), then
#       close its tab and its whole view tab, also when the user split it. Exit 1 and close nothing when there is no agent
#       in PANE, when the user focuses the view pane of PANE, when its workspace label
#       does not end with " workers", when its tab has other panes, or when the worker
#       stays busy. A view close failure is not a close failure. A view that does not
#       run the attach of PANE is no view. When the agent is gone but the pane is still
#       there, close it (an empty session line). With wait, no time limit: wait until
#       the view has no focus and the worker is idle, done or gone, then close. Remove
#       the line of PANE from the workers file.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"
use_user_session

# The workers run in the hidden Herdr session DISPATCH_SESSION, out of the sidebar of
# the user. HW calls Herdr there. Plain "$H" calls the session of the user (the
# orchestrator, the notifications and the view tabs).
S="$BOARD_SESSION"
HW=("$H" --session "$S")
HT=("${HW[@]}")
state="${XDG_STATE_HOME:-$HOME/.local/state}/board-orchestrator"
# The view tabs: one line "WORKER_PANE VIEW_PANE AGENT STATE" for each view of a worker.
# AGENT is the label of the report of the view, STATE its last reported state. A line
# from an older version has only the 2 panes. Each change runs under a lock on views-S.lock.
views="$state/views-$S"
# The lookup and the create of a workers workspace run under this lock.
WS_LOCK="$state/workspace-$S.lock"

# The workers: one line "PANE<tab>MODE<tab>BOARD<tab>REPORT" for each worker that start
# opened. A new orchestrator finds the report of a running worker here. Each change runs
# under a lock on workers-S.lock.
workers="$state/workers-$S"

# Remove the line of the worker pane $1 from the workers file. With $2, then add the
# line $1<tab>$2 (a pane ID can be reused).
set_worker() (
  mkdir -p "$state"
  exec 9>>"$workers.lock"
  flock 9
  tmp=$(mktemp "$workers.XXXXXX")
  { [ ! -f "$workers" ] || awk -F '\t' -v p="$1" '$1 != p' "$workers"; } >"$tmp"
  [ -z "${2:-}" ] || printf '%s\t%s\n' "$1" "$2" >>"$tmp"
  mv "$tmp" "$workers"
)

# Print the view pane of the worker pane $1 from the views file, or nothing.
view_of() {
  [ -f "$views" ] || return 0
  awk -v p="$1" '$1 == p { v = $2 } END { if (v != "") print v }' "$views"
}

# Remove the view of the worker pane $1 from the views file. With $2, then add the
# view $2 for it.
set_view() (
  mkdir -p "$state"
  exec 9>>"$views.lock"
  flock 9
  tmp=$(mktemp "$views.XXXXXX")
  { [ ! -f "$views" ] || awk -v p="$1" '$1 != p' "$views"; } >"$tmp"
  [ -z "${2:-}" ] || printf '%s %s\n' "$1" "$2" >>"$tmp"
  mv "$tmp" "$views"
)

# The red views: one line "WORKER_PANE VIEW_PANE AGENT COMPLETION_SEQ" for each view
# that shows reported blocked. AGENT is the label of the report. It is never empty, so
# it comes before the seq, which can be empty. Each change runs under a lock on marks-S.lock.
marks="$state/marks-$S"

# Remove the line of the worker pane $1 from the marks file. With $2, then add the
# line "$1 $2".
set_mark() (
  mkdir -p "$state"
  exec 9>>"$marks.lock"
  flock 9
  tmp=$(mktemp "$marks.XXXXXX")
  { [ ! -f "$marks" ] || awk -v p="$1" '$1 != p' "$marks"; } >"$tmp"
  [ -z "${2:-}" ] || printf '%s %s\n' "$1" "$2" >>"$tmp"
  mv "$tmp" "$marks"
)

# Print the agent label of the view of the worker pane $1: the project of the worker,
# the folder name of the main worktree of its cwd, else "worker". A project named claude
# also gives "worker": sync-name.sh renames each claude from its title, and the
# orchestrator lookups take each claude as a claude of the user.
view_label() {
  local cwd agent=worker
  cwd=$("${HW[@]}" pane get "$1" 2>/dev/null |
    jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null) || cwd=""
  [ -z "$cwd" ] || [ ! -d "$cwd" ] || agent=$(basename "$(main_worktree "$cwd")")
  [ "$agent" != claude ] || agent=worker
  printf '%s\n' "$agent"
}

# Print "VIEW AGENT STATE NAME" of the view of the worker pane $1 from the views file. A
# missing STATE (an older line) or a released view gives "-"; a missing NAME gives "-".
view_line() {
  awk -v p="$1" '$1 == p { l = $2 " " ($3 == "" ? "-" : $3) " " ($4 == "" ? "-" : $4) " " ($5 == "" ? "-" : $5) }
    END { print l }' "$views" 2>/dev/null
}

# Write the line of the view of the worker pane $1: VIEW AGENT STATE NAME ("-" for none).
write_view() {
  set_view "$1" "$2 $3 ${4:--} ${5:--}"
}

# Report the view of the worker pane $1 to Herdr as an agent in the state $2 (working,
# idle, blocked or unknown). reviewr sends its notes only to an agent of its workspace,
# and a text sent to the view goes through the attach to the worker. Keep the state in
# the views file: a report with no change is not sent again. Return 1 when the report
# fails. A plain report on the claude pane does not hold: Herdr reads the state of
# claude from its screen. After a release, give the view its worker name again.
report_view() {
  local view agent old vname message=()
  read -r view agent old vname <<<"$(view_line "$1")"
  [ -n "$view" ] || return 0
  [ "$2" != "$old" ] || return 0
  if [ "$2" = - ]; then
    release_view "$1"
    return 0
  fi
  [ "$agent" != - ] || agent=$(view_label "$1")
  [ "$2" != blocked ] || message=(--message "The worker waits for the user.")
  "$H" pane report-agent "$view" --source board-orchestrator --agent "$agent" --state "$2" \
    ${message[@]+"${message[@]}"} --seq "$(now_ns)" >/dev/null 2>&1 || return 1
  write_view "$1" "$view" "$agent" "$2" "$vname"
  [ "$old" != - ] || [ "$vname" = - ] || "$H" agent rename "$view" "$vname" >/dev/null 2>&1 || true
}

# Release the report of the view of the worker pane $1, and keep the view: the worker is
# gone, and a new claude in its pane can come.
release_view() {
  local view agent old vname
  read -r view agent old vname <<<"$(view_line "$1")"
  [ -n "$view" ] && [ "$old" != - ] || return 0
  [ "$agent" != - ] || agent=worker
  "$H" pane release-agent "$view" --source board-orchestrator --agent "$agent" \
    --seq "$(now_ns)" >/dev/null 2>&1 || true
  write_view "$1" "$view" "$agent" - "$vname"
}

# Report the view pane $2 of the worker pane $1 as blocked (red), and keep the completion
# seq $3 of the worker: the view stays red until the worker works or ends a new turn.
# The mark comes first: a status event of count-watch between the 2 steps then sees the
# mark and does not report the view idle. A failed report leaves no mark.
mark_view() {
  local view agent old vname
  read -r view agent old vname <<<"$(view_line "$1")"
  [ "$agent" != - ] || agent=$(view_label "$1")
  set_mark "$1" "$2 $agent $3"
  # Force the report: the state can be blocked from a permission prompt.
  write_view "$1" "$2" "$agent" - "$vname"
  report_view "$1" blocked || set_mark "$1"
}

# Copy the status $2 (with the completion seq $3) of the worker pane $1 to its view. A
# view is a Herdr agent only when it is red (the worker ended a turn and waits for the
# user), or when a reviewr is open in its tab: reviewr sends its notes only to an agent.
# Else the report is released and the view leaves the agent list. A red view stays
# blocked while the worker waits after the turn of the mark. A mark of another view is
# old: drop it. A view whose pane is gone, or that no longer runs the attach of the
# worker, is no view: forget it. A failed check keeps the view. The mark goes only after
# the new state is reported.
sync_view() {
  local line view mview agent mseq want old clear="" info
  view=$(view_of "$1")
  [ -n "$view" ] || return 0
  if [ -f "$marks" ]; then
    line=$(awk -v p="$1" '$1 == p { l = $2 " " $3 " " $4 } END { print l }' "$marks")
    if [ -n "$line" ]; then
      read -r mview agent mseq <<<"$line"
      if [ "$mview" != "$view" ]; then
        set_mark "$1"
      else
        [ "$2" = working ] || [ "$3" != "$mseq" ] || return 0
        clear=1
      fi
    fi
  fi
  if ! "$H" pane get "$view" >/dev/null 2>&1; then
    set_view "$1"
    set_mark "$1"
    return 0
  fi
  if info=$("$H" pane process-info --pane "$view" 2>/dev/null); then
    if ! view_valid "$view" "$1"; then
      set_view "$1"
      set_mark "$1"
      return 0
    fi
  else
    return 0
  fi
  want=-
  if reviewr_in_tab "$view"; then
    case "$2" in
      working) want=working ;;
      blocked) want=blocked ;;
      idle | done) want=idle ;;
      *) want=unknown ;;
    esac
  fi
  read -r _ _ old _ <<<"$(view_line "$1")"
  if [ "$want" != "$old" ] || [ -n "$clear" ]; then
    report_view "$1" "$want" || return 0
    [ -z "$clear" ] || set_mark "$1"
  fi
}

# Sync the view of the worker pane $1: read the status of the worker, and give the view
# the worker name when it has none. A worker that is gone releases its view.
sync_worker() {
  local agent status cseq name view vagent vstate vname
  read -r view vagent vstate vname <<<"$(view_line "$1")"
  [ -n "$view" ] || return 0
  if ! agent=$("${HW[@]}" agent get "$1" 2>/dev/null); then
    release_view "$1"
    return 0
  fi
  IFS=$'\x1f' read -r status cseq name < <(jq -r '.result.agent
    | [.agent_status // "", (.completion_seq // "" | tostring), .name // ""] | join("\u001f")' <<<"$agent" 2>/dev/null) ||
    status="" cseq="" name=""
  if [ "$vname" = - ] && [ -n "$name" ]; then
    write_view "$1" "$view" "$vagent" "$vstate" "$name"
  fi
  sync_view "$1" "$status" "$cseq"
}

# Return 0 when the pane $1 of the session of the user runs `herdr --session S agent
# attach $2`. A view pane ID can be reused, or the attach can end.
view_valid() {
  [ -n "$2" ] && runs_attach "$1" "$2"
}

# Return 0 when the user focuses the view pane of the worker pane $1 (as close).
view_focused() {
  local view info
  view=$(view_of "$1")
  [ -n "$view" ] && info=$("$H" pane get "$view" 2>/dev/null) && view_valid "$view" "$1" &&
    [ "$(jq -r '.result.pane.focused // false | tostring' <<<"$info" 2>/dev/null)" = true ]
}

# One pass of views-restore under a lock. Return 0 when nothing is left to wait for, 1
# when a worker, the hidden session or an orchestrator is not back yet, or a step failed.
# A pass is idempotent: a worker with a valid view and a tab with a program change nothing.
restore_pass() (
  mkdir -p "$state"
  exec 9>>"$state/views-restore-$S.lock"
  flock -w 60 9 || exit 1
  [ -s "$workers" ] || exit 0
  pending=0 cleaned="|"
  while IFS=$'\t' read -r -u 5 pane _ board _; do
    [ -n "$pane" ] || continue
    [ -n "$board" ] || continue
    if ! "${HW[@]}" agent get "$pane" 2>/dev/null | jq -e '.result.agent.agent == "claude"' >/dev/null 2>&1; then
      pending=1
      continue
    fi
    if ! ws=$(board_workspace_id "$board"); then
      pending=1
      continue
    fi
    if [ -z "$ws" ]; then
      printf 'views-restore: no workspace %s orchestrator. Skip %s.\n' "$board" "$pane" >&2
      continue
    fi
    # The orchestrator claude resumes after the workspace: its tab is not for closing.
    if ! orch=$(orchestrator_pane "$board"); then
      pending=1
      continue
    fi
    if [[ "$cleaned" != *"|$board|"* ]]; then
      cleaned="$cleaned$board|"
      if ! panes=$("$H" pane list --workspace "$ws" 2>/dev/null); then
        pending=1
        continue
      fi
      orch_tab=$(jq -r --arg p "$orch" '[.result.panes[]? | select(.pane_id == $p) | .tab_id][0] // empty' <<<"$panes" 2>/dev/null) || orch_tab=""
      while IFS= read -r -u 6 tab; do
        [ -n "$tab" ] || continue
        # Close a tab only when every pane of it shows the login shell and nothing else.
        bare=1
        while IFS= read -r -u 7 tpane; do
          if ! info=$("$H" pane process-info --pane "$tpane" 2>/dev/null) ||
            ! jq -e '[.result.process_info.foreground_processes[]? | (.argv[0] // "") | split("/")[-1] | ltrimstr("-")]
              | length > 0 and all(IN("zsh", "bash", "sh", "dash", "fish", "ksh"))' <<<"$info" >/dev/null 2>&1; then
            bare=""
            break
          fi
        done 7< <(jq -r --arg t "$tab" '.result.panes[]? | select(.tab_id == $t) | .pane_id' <<<"$panes" 2>/dev/null)
        [ -n "$bare" ] || continue
        if "$H" tab close "$tab" >/dev/null 2>&1; then
          printf 'views-restore: closed the tab %s of %s (only shells).\n' "$tab" "$ws" >&2
        else
          printf 'views-restore: could not close the tab %s.\n' "$tab" >&2
          pending=1
        fi
      done 6< <(jq -r --arg t "$orch_tab" '[.result.panes[]? | .tab_id] | unique[] | select(. != $t)' <<<"$panes" 2>/dev/null)
    fi
    view=$(view_of "$pane")
    if [ -n "$view" ] && "$H" pane get "$view" >/dev/null 2>&1 && view_valid "$view" "$pane"; then
      continue
    fi
    # The show logic, as from the orchestrator: the view tab opens with no focus.
    if view=$(HERDR_WORKSPACE_ID=$ws HERDR_PANE_ID=$orch bash "$0" show "$pane" 5<&- 6<&- 7<&- 9>&-); then
      printf 'views-restore: view %s for %s in %s.\n' "$view" "$pane" "$ws" >&2
    else
      printf 'views-restore: could not open a view for %s.\n' "$pane" >&2
      pending=1
    fi
  done 5<"$workers"
  exit "$pending"
)

# The calls that push or write to a forge. policy-set adds each one of the forge.
GH_PUSH_RULES=('Bash(git push*)' 'Bash(git -C * push*)' 'Bash(git -c * push*)' 'Bash(gh pr create*)'
  'Bash(gh pr comment*)' 'Bash(gh pr edit*)' 'Bash(gh pr ready*)' 'Bash(gh pr close*)'
  'Bash(gh issue create*)' 'Bash(gh issue comment*)' 'Bash(gh issue edit*)')
FORGEJO_PUSH_RULES=('Bash(git push*)' 'Bash(git -C * push*)' 'Bash(git -c * push*)'
  mcp__forgejo__create_pull_request mcp__forgejo__update_pull_request
  mcp__forgejo__create_issue mcp__forgejo__update_issue mcp__forgejo__create_issue_comment
  mcp__forgejo__edit_issue_comment mcp__forgejo__issue_state_change)
# The calls that merge a PR. A worker never merges: policy-set adds each one of the
# forge to deny.
GH_MERGE_RULES=('Bash(gh pr merge*)' 'Bash(tea pr merge*)' 'Bash(tea pulls merge*)'
  'mcp__forgejo__merge_pull_request')
FORGEJO_MERGE_RULES=('Bash(tea pr merge*)' 'Bash(tea pulls merge*)' 'mcp__forgejo__merge_pull_request')
# The rules of the old policy-set that do more than push and comment. policy-set
# removes each one from allow and ask.
OLD_RULES=('Bash(gh pr merge*)' 'Bash(gh pr review*)' 'Bash(gh release*)' 'Bash(gh repo create*)'
  'Bash(gh gist*)' 'Bash(gh api -X*)' 'Bash(gh api --method*)')
# The gh rules that policy-set wrote. For Forgejo, policy-set removes each one from
# allow, ask and deny.
GH_RULES=('Bash(gh pr create*)' 'Bash(gh pr comment*)' 'Bash(gh pr edit*)' 'Bash(gh pr ready*)'
  'Bash(gh pr close*)' 'Bash(gh issue create*)' 'Bash(gh issue comment*)' 'Bash(gh issue edit*)'
  "${OLD_RULES[@]}")

# Return 0 when the screen of the worker pane $1 shows a background job (a shell or a
# subagent): Claude Code can end its turn while one runs. Return 1 when the read fails.
# The "← N agent" part shows also with no job: do not use it.
screen_job() {
  local screen
  screen=$("${HW[@]}" pane read "$1" --source visible 2>/dev/null) || return 1
  tail -n 15 <<<"$screen" | awk '
    / · [0-9]+ shells?( ·|$)/ && (/⏵/ || /to manage/) { job = 1 }
    /^ +(◯ |● main)/ { job = 1 }
    / · done / { last = $0 }
    END { exit !(job || last ~ /still running/) }'
}

# One check of the worker in $pane for wait and watch. Return 1 when Herdr finds no
# agent. Else set status, name, seq, out_seq, base_seq, job and need (blocked, idle,
# idle-job or empty) from the state idles, idle_seq, seen and seen_seq, and keep
# last_name. need is set only when it is not the SEEN need.
check_need() {
  local agent
  agent=$("${HW[@]}" agent get "$pane" 2>/dev/null) || return 1
  IFS=$'\x1f' read -r status name seq cseq < <(jq -r '.result.agent
    | [.agent_status // "", .name // "", (.state_change_seq // "" | tostring), (.completion_seq // "" | tostring)]
    | join("\u001f")' <<<"$agent" 2>/dev/null) || status="" name="" seq="" cseq=""
  sync_view "$pane" "$status" "$cseq"
  # A new status can change the state of the orchestrator workspace of the board.
  if [ "$status" != "${last_status-}" ]; then
    last_status=$status
    [ -n "${worker_board+x}" ] || worker_board=$([ ! -f "$workers" ] ||
      awk -F '\t' -v p="$pane" '$1 == p { b = $3 } END { print b }' "$workers")
    [ -z "$worker_board" ] || show_worker_count "$worker_board"
  fi
  # The screen cannot tell "I wait for my job" from "I need you": a screen with a job
  # gives the need idle-job, and the orchestrator reads the last message.
  job=""
  case "$status" in
    idle | done) if screen_job "$pane"; then job=1; fi ;;
  esac
  # For a stop, the completion seq: a view of the pane turns done into idle and
  # changes state_change_seq, but not completion_seq. With no completion seq, a move
  # between done and idle is no change: compare the status only.
  out_seq=$seq raw_seq=$seq
  case "$status" in
    idle | done)
      seq=$cseq
      [ -z "$cseq" ] || out_seq=$cseq
      ;;
  esac
  [ -z "$name" ] || last_name=$name
  # With no seq from Herdr or in SEEN, SEEN ends when the status changes.
  fallback=""
  [ -n "$seq" ] && [ -n "$seen_seq" ] || fallback=1
  need=""
  case "$status" in
    blocked) idles=0 need=blocked ;;
    idle | done)
      # A short idle can occur before the work starts: two checks in a row with the same seq.
      # A change between idle and idle-job starts the count again.
      if [ "$idles" -gt 0 ] && [ "$seq/$job" = "$idle_seq" ]; then idles=$((idles + 1)); else idles=1; fi
      idle_seq=$seq/$job
      [ "$idles" -lt 2 ] || need=idle${job:+-job}
      [ -z "$fallback" ] || [ "$seen" != blocked ] || seen=""
      ;;
    *)
      idles=0
      [ -z "$fallback" ] || seen=""
      ;;
  esac
  # The seq of a stop: the completion seq, else the state seq.
  base_seq=${cseq:-$raw_seq}
  if [ -n "$need" ] && ! { [ "$need" != "$seen" ] || { [ -z "$fallback" ] && [ "$seq" != "$seen_seq" ]; }; }; then
    need=""
  fi
  return 0
}

# The Herdr events of the worker in $pane, for wait and watch. A status change then
# shows at once, not at the next poll. No event tells of the report file or of the
# job on the screen: the poll stays as the limit of each wait. Each problem of the
# event path gives the plain sleep: the events only make the wait shorter.
# Subscribe once, before the first check: a change between a check and the next wait
# is then in the pipe, not lost. ev_dir holds the 2 fifos of nc, one for each process.
# nc runs as a plain background job: bash 3.2 (macOS) sets no $! for a process
# substitution.
ev_dir="" ev_pid="" ev_on=""
pane_events_open() {
  local sock request line
  sock=$("$H" session list --json 2>/dev/null | jq -r --arg s "$S" \
    '[.sessions[]? | select(.name == $s and .running == true) | .socket_path // empty][0] // empty' 2>/dev/null) || sock=""
  [ -n "$sock" ] || return 1
  mkdir -p "$state"
  ev_dir=$(mktemp -d "$state/events.XXXXXX") || { ev_dir=""; return 1; }
  mkfifo "$ev_dir/in" "$ev_dir/out" || return 1
  "${DISPATCH_NC:-nc}" -U "$sock" <"$ev_dir/in" >"$ev_dir/out" 2>/dev/null &
  ev_pid=$!
  # Each open waits for the other end: nc opens its stdin first, then its stdout.
  exec 7>"$ev_dir/in" 6<"$ev_dir/out"
  request=$(jq -cn --arg p "$pane" '{id: "dispatch-wait", method: "events.subscribe", params: {subscriptions: [
    {type: "pane.agent_status_changed", pane_id: $p}, {type: "pane.exited"}, {type: "pane.closed"}, {type: "pane.agent_detected"}]}}')
  # A subshell: an nc that closed the connection must not stop the script with SIGPIPE.
  (printf '%s\n' "$request" >&7) 2>/dev/null || return 1
  while IFS= read -r -t 5 line <&6; do
    case "$line" in
      *'"subscription_started"'*)
        ev_on=1
        return 0
        ;;
      *'"error"'*) return 1 ;;
    esac
  done
  return 1
}

# Stop nc and remove its fifos. It runs at each exit, also after a failed open.
pane_events_close() {
  ev_on=""
  [ -z "$ev_pid" ] || kill "$ev_pid" 2>/dev/null || true
  exec 6<&- 7>&-
  [ -z "$ev_pid" ] || wait "$ev_pid" 2>/dev/null || true
  ev_pid=""
  [ -z "$ev_dir" ] || rm -rf "$ev_dir"
  ev_dir=""
}

# Wait $1 seconds, or less when an event of $pane comes. read -t takes whole seconds
# in bash 3.2. With no events, or when nc stops, sleep as before.
pane_event_wait() {
  local end=$((SECONDS + $1)) left line pid rc
  while [ -n "$ev_on" ]; do
    left=$((end - SECONDS))
    [ "$left" -gt 0 ] || return 0
    rc=0
    IFS= read -r -t "$left" line <&6 || rc=$?
    # A status above 128 is the end of the time. Another error is the end of the
    # connection: sleep for the rest of the time.
    [ "$rc" -le 128 ] || return 0
    if [ "$rc" -ne 0 ]; then
      ev_on=""
      break
    fi
    pid=$(jq -r '.data.pane_id // empty' <<<"$line" 2>/dev/null) || pid=""
    [ "$pid" != "$pane" ] || return 0
  done
  left=$((end - SECONDS))
  [ "$left" -le 0 ] || sleep "$left"
}

# The wait before the next check of wait and watch. The idle rule needs 2 idle checks in
# a row: a short idle can occur before the work starts. With events, the second check
# comes after DISPATCH_SETTLE seconds, not after the poll: an event (the worker works
# again) can wake it earlier, and that check then starts the count again. Without
# events, keep the poll as the gap: no event can then show the end of a short idle.
next_check() {
  local wait=${DISPATCH_POLL:-30}
  if [ -n "$ev_on" ] && [ "$idles" -eq 1 ] && [ "${DISPATCH_SETTLE:-5}" -lt "$wait" ]; then
    wait=${DISPATCH_SETTLE:-5}
  fi
  pane_event_wait "$wait"
}

# Start the events for wait and watch, with a cleanup on each exit path.
start_pane_events() {
  trap pane_events_close EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  pane_events_open || pane_events_close
}

# Print the claude panes of the workspaces "<board> workers" for count-watch, sorted,
# one for each line. $1 has one line "WORKSPACE_ID<tab>BOARD" for each of these
# workspaces, $2 is the agent list of the hidden session. The listener compares two
# results to find a new or a closed worker.
worker_panes() {
  jq -r --arg b "$1" '[$b | split("\n")[] | select(. != "") | split("\t")[0]] as $ids
    | [.result.agents[]? | select(.agent == "claude" and (.workspace_id as $i | $ids | index([$i])))
      | .pane_id] | sort[]' <<<"$2"
}

case "${1:-}" in
  policy)
    push_policy "${2:-}"
    ;;
  policy-set)
    cwd="${2:-}" kind="${3:-}"
    if [ "$kind" != allow ] && [ "$kind" != ask ]; then
      printf 'usage: dispatch.sh policy-set CWD allow|ask\n' >&2
      exit 2
    fi
    if [ ! -d "$cwd" ]; then
      printf 'dispatch: %s is not a folder.\n' "$cwd" >&2
      exit 2
    fi
    # Forgejo is the default: only github.com uses gh.
    url=$(git -C "$cwd" remote get-url origin 2>/dev/null) || url=
    host=${url#*://}
    host=${host#*@}
    host=${host%%[:/]*}
    if [ "$host" = github.com ]; then
      push_rules=("${GH_PUSH_RULES[@]}")
      merge_rules=("${GH_MERGE_RULES[@]}")
      gh_rules=()
    else
      push_rules=("${FORGEJO_PUSH_RULES[@]}")
      merge_rules=("${FORGEJO_MERGE_RULES[@]}")
      gh_rules=("${GH_RULES[@]}")
    fi
    file="$cwd/.claude/settings.local.json"
    current=$(read_settings "$file") || exit 2
    mkdir -p "$cwd/.claude"
    tmp=$(mktemp "$file.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    if ! jq --arg k "$kind" --argjson push "$(jq -n '$ARGS.positional' --args "${push_rules[@]}")" \
      --argjson merge "$(jq -n '$ARGS.positional' --args "${merge_rules[@]}")" \
      --argjson drop "$(jq -n '$ARGS.positional' --args "${OLD_RULES[@]}")" \
      --argjson gh "$(jq -n '$ARGS.positional' --args "${gh_rules[@]}")" '
      def add($k; $r): .permissions[$k] = ((.permissions[$k] // []) as $old | $old + [$r[] | select(. as $x | $old | index([$x]) | not)]);
      reduce ("allow", "ask") as $l (.;
        if .permissions[$l] == null then . else .permissions[$l] |= map(select(. as $x | $drop | index([$x]) | not)) end)
      | reduce ("allow", "ask", "deny") as $l (.;
        if .permissions[$l] == null then . else .permissions[$l] |= map(select(. as $x | $gh | index([$x]) | not)) end)
      # ask wins over allow: remove the push rules from the other list first.
      | (if $k == "allow" then "ask" else "allow" end) as $o
      | (if .permissions[$o] == null then . else .permissions[$o] |= map(select(. as $x | $push | index([$x]) | not)) end)
      | add($k; $push) | add("deny"; $merge)' <<<"$current" >"$tmp" || [ ! -s "$tmp" ]; then
      printf 'dispatch: could not write %s.\n' "$file" >&2
      exit 2
    fi
    # The macOS chmod has no --reference.
    if [ -e "$file" ]; then
      chmod "$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file")" "$tmp"
    else
      chmod 644 "$tmp"
    fi
    mv "$tmp" "$file"
    trap - EXIT
    push_policy "$cwd"
    ;;
  start)
    mode="${2:-}" cwd="${3:-}" name="${4:-}" prompt_file="${5:-}"
    if [ "$mode" != task ] && [ "$mode" != auto ] || [ -z "$cwd" ] || [ -z "$name" ] || [ ! -f "$prompt_file" ]; then
      printf 'usage: dispatch.sh start task|auto CWD NAME PROMPT_FILE\n' >&2
      exit 2
    fi
    # The board comes from the workspace of the caller in the session of the user. The
    # IDs of the hidden session mean nothing there.
    if [ "$PANE_SESSION" = "$BOARD_SESSION" ]; then
      printf 'dispatch: start runs only in the orchestrator, not in the hidden session %s.\n' "$BOARD_SESSION" >&2
      exit 2
    fi
    if [ ! -d "$cwd" ]; then
      printf 'dispatch: %s is not a folder.\n' "$cwd" >&2
      exit 2
    fi
    cwd=$(cd -- "$cwd" >/dev/null && pwd -P)
    # No notify in these checks: the caller reads stderr, and no herdr call may happen.
    rules=()
    if [ "$mode" = task ]; then
      policy=$(push_policy "$cwd") || exit 2
    fi
    if [ "$mode" = task ] && [ "$policy" = missing ]; then
      printf 'dispatch: no push policy for %s: run dispatch.sh policy-set\n' "$cwd" >&2
      exit 2
    fi
    if [ "$mode" = auto ]; then
      readonly_file="$cwd/.claude/settings.readonly.json"
      if [ ! -f "$readonly_file" ] || ! list=$(jq -r '.permissions.allow // [] | .[] | strings' "$readonly_file" 2>/dev/null); then
        printf 'dispatch: %s is missing or is not valid JSON.\n' "$readonly_file" >&2
        exit 2
      fi
      while IFS= read -r rule; do
        [ -z "$rule" ] || rules+=("$rule")
      done <<<"$list"
      if [ "${#rules[@]}" -eq 0 ]; then
        printf 'dispatch: %s has no rule in permissions.allow.\n' "$readonly_file" >&2
        exit 2
      fi
    fi
    if [ -z "${HERDR_WORKSPACE_ID:-}" ]; then
      printf 'dispatch: HERDR_WORKSPACE_ID is empty. Run this in a Herdr pane.\n' >&2
      exit 2
    fi
    slug=$(agent_slug "$name")
    dir="${XDG_STATE_HOME:-$HOME/.local/state}/board-orchestrator"
    mkdir -p "$dir"
    report="$dir/${slug:-worker}-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM.md"
    claude_args=()
    footer="When you finish, write your report to $report. Do not merge, deploy or change production. Write the report in one Write call, as your last step. Do not edit the vault. When the user asks for a change to the board or to a task note, write it in the report under a heading ## Vault changes, one change for each item. For a new task, write only its title, its project, its priority and one context line: the orchestrator writes the card in the board format, so do not read the vault for it. For a change to existing text, give the note path and the exact old and new text. When the user answers you or asks for more work after your report, write the full report again when you finish. The new report replaces the old one. After the first line, write a section ## Result of at most 10 lines: the result, and the PR, commit or issue links. You run in a hidden Herdr session: the user sees you only in a view tab. Do not open a Herdr pane, tab or plugin pane, for example reviewr: the user cannot see it. Give no link to a Herdr pane. The user opens reviewr with ctrl+b d in your view."
    if [ "$mode" = task ]; then
      footer="$footer Start the report with one line: RESULT: DONE when the work of the card is complete, or RESULT: WAITS FOR USER when the user must act (a PR to review or merge, a question, a decision)."
    fi
    if [ "$mode" = auto ]; then
      # --allowedTools takes many values, so it must be the last option.
      claude_args+=(--setting-sources user --settings "$readonly_file" --permission-mode dontAsk)
      [ ! -f "$cwd/.mcp.json" ] || claude_args+=(--mcp-config "$cwd/.mcp.json")
      # A claude rule for an absolute path starts with a double slash. Edit also covers Write.
      claude_args+=(--allowedTools "Edit(/$report)")
      footer="$footer Start the report with one line: STATUS: OK, STATUS: STOP or STATUS: REFUSED. Write STATUS: REFUSED when claude refused a call that the check needs, and add one line REFUSED: <command> for each refused call. Give each value with OK or STOP. Do not trip a kill switch."
      footer="$footer"$'\n\n'"You can use only these tools. Claude refuses all other calls."
      footer="$footer"$'\n'"$(printf '%s\n' "${rules[@]}")"
      footer="$footer"$'\n'"You can also write the report file with the Edit or Write tool."
      footer="$footer"$'\n'"Run each command exactly in the form of its rule, from the start folder. Do not add another cd or -C, and do not add ; or &&. If a call is refused, do not try another form: write the refused command in the report."
    fi
    # The worker is a tab in the workers workspace of the board, in the hidden session.
    # The board comes from the label of the orchestrator workspace, in the session of
    # the user. An old label has the number of workers: "<board> orchestrator · 2 workers".
    if ! label=$("$H" workspace get "$HERDR_WORKSPACE_ID" 2>/dev/null |
      jq -r '.result.workspace.label // empty' 2>/dev/null) || [ -z "$label" ]; then
      printf 'dispatch: workspace lookup failed for %s. Start no worker.\n' "$HERDR_WORKSPACE_ID" >&2
      exit 1
    fi
    label=${label%% · *}
    mkdir -p "$state"
    # A new server has new pane IDs: the old views mean nothing.
    ensure_session "$S" "$views" || exit 1
    detach "$here/dispatch.sh" count-watch >/dev/null 2>&1 </dev/null
    # No fallback workspace: the IDs of the session of the user mean nothing in S.
    # When claude does not start, the pane can still exist: print it, so that the
    # orchestrator can show it.
    started=1
    pane=$(workspace_pane "${label% orchestrator} workers" "$cwd" --no-focus "" "" \
      ${claude_args[@]+"${claude_args[@]}"}) || started=""
    # Record the worker before the prompts: when a prompt fails, show must still find the
    # board of the worker. The report name starts with the slug, and the agent name is the
    # slug (or the slug with -N): workers finds the report of a worker with no line from that.
    [ -z "$pane" ] || set_worker "$pane" "$mode"$'\t'"${label% orchestrator}"$'\t'"$report"
    if [ -z "$started" ]; then
      [ -z "$pane" ] || printf '%s\n' "$pane"
      notify "Claude did not start in the new tab."
      exit 1
    fi
    # /rename first: the session title then gives the agent name, and the name lasts.
    "${HW[@]}" agent prompt "$pane" "/rename $name" >/dev/null || true
    if ! "${HW[@]}" agent prompt "$pane" "$(<"$prompt_file")"$'\n\n'"$footer" >/dev/null; then
      printf '%s\n' "$pane"
      notify "Claude in $pane did not get the prompt."
      exit 1
    fi
    rename_agent "$pane" "$slug"
    show_worker_count "${label% orchestrator}"
    printf '%s\n%s\n' "$pane" "$report"
    ;;
  wait)
    pane="${2:?pane}" report="${3:?report}" seen="${4:-}" seen_seq="${5:-}"
    misses=0 idles=0 idle_seq="" last_name=""
    start_pane_events
    while true; do
      [ ! -s "$report" ] || exit 0
      if check_need; then
        misses=0
        if [ -n "$need" ]; then
          [ ! -s "$report" ] || exit 0
          case "$need" in
            blocked) notify_need "$pane" "$name" "The worker waits at a permission prompt." ;;
            idle) notify_need "$pane" "$name" "The worker ended its turn with no report." ;;
          esac
          printf '%s\n' "$need${out_seq:+ $out_seq}"
          exit 3
        fi
      else
        # The worker can write the report and exit after the first check.
        [ ! -s "$report" ] || exit 0
        misses=$((misses + 1))
        if [ "$misses" -ge 3 ]; then
          notify_need "$pane" "$last_name" "The worker is gone with no report."
          printf 'dispatch: the agent in %s stopped with no report.\n' "$pane" >&2
          exit 1
        fi
      fi
      next_check
    done
    ;;
  last)
    pane="${2:?pane}"
    if ! agent=$("${HW[@]}" agent get "$pane" 2>/dev/null); then
      printf 'dispatch: no agent in %s.\n' "$pane" >&2
      exit 1
    fi
    session=$(jq -r '.result.agent.agent_session.value // empty' <<<"$agent" 2>/dev/null) || session=""
    text=""
    if [ -n "$session" ]; then
      file=""
      for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$session.jsonl"; do
        [ ! -f "$f" ] || file=$f
      done
      # Transcripts can be large: read from the end and stop at the first match.
      if [ -n "$file" ]; then
        # macOS has no tac: its tail -r prints the lines in reverse order.
        text=$( { if command -v tac >/dev/null; then tac "$file"; else tail -r "$file"; fi; } | while IFS= read -r line; do
          case "$line" in *'"type":"assistant"'*) ;; *) continue ;; esac
          t=$(jq -r 'select(.type == "assistant") | [.message.content[]? | select(.type == "text") | .text] | join("\n")' <<<"$line" 2>/dev/null) || t=""
          if [ -n "$t" ]; then
            printf '%s' "$t"
            break
          fi
        done) || true
      fi
    fi
    if [ -n "$text" ]; then
      [ "${#text}" -le 3000 ] || text=${text: -3000}
      printf '%s\n' "$text"
    else
      "${HW[@]}" pane read "$pane" --source visible 2>/dev/null | tail -n 40 || true
    fi
    ;;
  watch)
    pane="${2:?pane}" report="${3:?report}" seen="${4:-}" seen_seq="${5:-}"
    # The content and the mtime: a rewrite with the same text is also a change.
    state() { { cksum <"$report" && file_mtime "$report"; } 2>/dev/null || printf 'missing\n'; }
    start_state=$(state)
    misses=0 idles=0 idle_seq="" last_name="" base="$seen_seq" based=""
    [ -z "$seen_seq" ] || based=1
    start_pane_events
    while true; do
      [ "$(state)" = "$start_state" ] || exit 0
      if check_need; then
        misses=0
        # The baseline: SEQ, else the seq of the first check. A new turn end has
        # another seq.
        if [ -z "$based" ]; then
          base=$base_seq based=1
        fi
        case "$need" in
          idle | idle-job) [ "$out_seq" != "$base" ] || need="" ;;
        esac
        if [ -n "$need" ]; then
          [ "$(state)" = "$start_state" ] || exit 0
          # No notification for a stop: the orchestrator reads the last message.
          [ "$need" != blocked ] || notify_need "$pane" "$name" "The worker waits at a permission prompt."
          printf '%s\n' "$need${out_seq:+ $out_seq}"
          exit 3
        fi
      else
        [ "$(state)" = "$start_state" ] || exit 0
        misses=$((misses + 1))
        if [ "$misses" -ge 3 ]; then
          printf 'dispatch: the agent in %s stopped and the report did not change.\n' "$pane" >&2
          exit 1
        fi
      fi
      next_check
    done
    ;;
  remind)
    pane="${2:?pane}" report="${3:?report}"
    while true; do
      if ! agent=$("${HW[@]}" agent get "$pane" 2>/dev/null); then
        printf 'dispatch: no agent in %s.\n' "$pane" >&2
        exit 1
      fi
      # Do not type in the worker while the user looks at it in its view.
      if ! view_focused "$pane"; then
        status=$(jq -r '.result.agent.agent_status // ""' <<<"$agent" 2>/dev/null) || status=""
        case "$status" in
          idle | done) ;;
          *)
            printf 'dispatch: the worker is working (%s). Send nothing.\n' "${status:-unknown}" >&2
            exit 1
            ;;
        esac
        if ! "${HW[@]}" agent prompt "$pane" "Write the report again to $report now, in one Write call. Give the full report for the current state, with a new first line in the same form as before. The new report replaces the old one." >/dev/null; then
          printf 'dispatch: could not prompt the worker in %s.\n' "$pane" >&2
          exit 1
        fi
        exit 0
      fi
      sleep "${DISPATCH_POLL:-30}"
    done
    ;;
  answer)
    pane="${2:?pane}" file="${3:?file}"
    if [ ! -s "$file" ]; then
      printf 'dispatch: the answer file %s is missing or empty.\n' "$file" >&2
      exit 2
    fi
    words=$(cat "$file")
    while true; do
      if ! agent=$("${HW[@]}" agent get "$pane" 2>/dev/null); then
        printf 'dispatch: no agent in %s.\n' "$pane" >&2
        exit 1
      fi
      status=$(jq -r '.result.agent.agent_status // ""' <<<"$agent" 2>/dev/null) || status=""
      # Text sent into a permission prompt can select an option: send only to an idle
      # or done worker, and never while the user looks at it in its view.
      case "$status" in
        idle | done)
          if ! view_focused "$pane"; then
            if ! "${HW[@]}" agent prompt "$pane" "The user answers through the orchestrator:

$words" >/dev/null; then
              printf 'dispatch: could not prompt the worker in %s.\n' "$pane" >&2
              exit 1
            fi
            exit 0
          fi
          ;;
      esac
      sleep "${DISPATCH_POLL:-30}"
    done
    ;;
  notify)
    pane="${2:?pane}"
    # A fixed body: report text is untrusted, so it never goes on the command line.
    case "${3:-}" in
      waits) body="The worker waits for the user." ;;
      stop) body="The worker found a STOP value." ;;
      refused) body="The allow list refused a command of the worker." ;;
      *)
        printf 'usage: dispatch.sh notify PANE waits|stop|refused\n' >&2
        exit 2
        ;;
    esac
    name=$("${HW[@]}" agent get "$pane" 2>/dev/null | jq -r '.result.agent.name // empty' 2>/dev/null) || name=""
    notify_need "$pane" "$name" "$body"
    ;;
  show)
    pane="${2:?pane}" mode="${3:-}"
    if [ -n "$mode" ] && [ "$mode" != need ]; then
      printf 'usage: dispatch.sh show PANE [need]\n' >&2
      exit 2
    fi
    # A caller in the session of the user is the orchestrator: the view goes to its own
    # workspace. A caller in the hidden session (a worker) has no workspace of the user:
    # the view goes to the workspace "<board> orchestrator" of the board of the worker.
    if [ "$PANE_SESSION" != "$BOARD_SESSION" ]; then
      if [ -z "${HERDR_WORKSPACE_ID:-}" ]; then
        printf 'dispatch: HERDR_WORKSPACE_ID is not set. Run this in a Herdr pane.\n' >&2
        exit 2
      fi
      target=$HERDR_WORKSPACE_ID
    else
      board=""
      [ ! -f "$workers" ] || board=$(awk -F '\t' -v p="$pane" '$1 == p { b = $3 } END { print b }' "$workers")
      if [ -z "$board" ]; then
        printf 'dispatch: no board for %s in the hidden session %s. Open no view.\n' "$pane" "$BOARD_SESSION" >&2
        exit 2
      fi
      if ! target=$(board_workspace_id "$board"); then
        printf 'dispatch: the workspace lookup failed. Open no view.\n' >&2
        exit 1
      fi
      # Closing the workspace stopped the orchestrator: do not open it again.
      if [ -z "$target" ]; then
        printf 'dispatch: the workspace %s orchestrator is gone. Open no view.\n' "$board" >&2
        exit 1
      fi
    fi
    if ! agent=$("${HW[@]}" agent get "$pane" 2>/dev/null); then
      printf 'dispatch: no agent in pane %s of session %s.\n' "$pane" "$S" >&2
      exit 1
    fi
    IFS=$'\x1f' read -r status cseq name < <(jq -r '.result.agent
      | [.agent_status // "", (.completion_seq // "" | tostring), .name // ""] | join("\u001f")' <<<"$agent" 2>/dev/null) ||
      status="" cseq="" name=""
    # Keep the name of the worker for the view. Herdr renames only an agent, so the
    # rename runs when the view gets its report (red, or a reviewr in its tab): the
    # reviewr picker then shows the name. A name that a pane of the user already has, or
    # a bad name, leaves the view with no name.
    report_shown() {
      read -r _ vagent vstate vname <<<"$(view_line "$pane")"
      if [ -n "$name" ] && [ "$vname" = - ]; then
        write_view "$pane" "$view" "$vagent" "$vstate" "$name"
      fi
      if [ -n "$mode" ]; then
        mark_view "$pane" "$view" "$cseq"
      else
        sync_view "$pane" "$status" "$cseq"
      fi
    }
    view=$(view_of "$pane")
    if [ -n "$view" ]; then
      if "$H" pane get "$view" >/dev/null 2>&1 && view_valid "$view" "$pane"; then
        report_shown
        printf '%s\n' "$view"
        exit 0
      fi
      set_view "$pane"
      set_mark "$pane"
    fi
    if ! created=$("$H" tab create --workspace "$target" --label "${name:-worker}" --no-focus 2>/dev/null) ||
      ! view=$(jq -r '.result.root_pane.pane_id // empty' <<<"$created" 2>/dev/null) || [ -z "$view" ]; then
      printf 'dispatch: could not open a view tab in %s.\n' "$target" >&2
      exit 1
    fi
    "$H" pane run "$view" "$(attach_command "$pane")" >/dev/null 2>&1 || true
    # Check that the attach runs: DISPATCH_ATTACH_WAIT seconds (3 by default).
    deadline=$((SECONDS + ${DISPATCH_ATTACH_WAIT:-3}))
    until view_valid "$view" "$pane"; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        printf 'dispatch: the view %s does not show %s. Close the view tab by hand.\n' "$view" "$pane" >&2
        exit 1
      fi
      sleep 0.2
    done
    set_view "$pane" "$view"
    set_mark "$pane"
    report_shown
    printf '%s\n' "$view"
    ;;
  close)
    pane="${2:?pane}" mode="${3:-}"
    if [ -n "$mode" ] && [ "$mode" != wait ]; then
      printf 'usage: dispatch.sh close PANE [wait]\n' >&2
      exit 2
    fi
    # 90 seconds by default: the Bash tool of the orchestrator stops a call after 120.
    # With wait, no limit.
    deadline=$((SECONDS + ${DISPATCH_CLOSE_WAIT:-90}))
    # Wait until the worker ended its turn: a close kills a turn that runs.
    while true; do
      # The focus of the worker pane means nothing in the hidden session. The user
      # looks at a worker in its view pane. A view that does not attach to this worker
      # is no view.
      view=$(view_of "$pane") view_tab="" view_focused=""
      if [ -n "$view" ]; then
        if view_info=$("$H" pane get "$view" 2>/dev/null) && view_valid "$view" "$pane"; then
          IFS=$'\x1f' read -r view_focused view_tab < <(jq -r '.result.pane
            | [(.focused // false | tostring), .tab_id // ""] | join("\u001f")' <<<"$view_info" 2>/dev/null) ||
            view_focused="" view_tab=""
        else
          set_view "$pane"
          set_mark "$pane"
        fi
      fi
      status="" session="" tab="" ws=""
      if agent=$("${HW[@]}" agent get "$pane" 2>/dev/null); then
        misses=0
        IFS=$'\x1f' read -r status session tab ws < <(jq -r '.result.agent
          | [.agent_status // "", .agent_session.value // "", .tab_id // "", .workspace_id // ""]
          | join("\u001f")' <<<"$agent" 2>/dev/null) || status=""
      elif info=$("${HW[@]}" pane get "$pane" 2>/dev/null); then
        # The user quit claude in the view: the pane stays. Close it too. A short miss
        # can occur on a busy worker: gone only after 3 misses in a row.
        misses=$((${misses:-0} + 1))
        if [ "$misses" -lt 3 ]; then
          poll=${DISPATCH_POLL:-30}
          # Also here, do not sleep past the deadline.
          if [ "$mode" != wait ]; then
            left=$((deadline - SECONDS))
            if [ "$left" -le 0 ]; then
              printf 'dispatch: the worker in %s is still unknown. Close nothing.\n' "$pane" >&2
              exit 1
            fi
            [ "$poll" -le "$left" ] || poll=$left
          fi
          sleep "$poll"
          continue
        fi
        status=gone
        IFS=$'\x1f' read -r tab ws < <(jq -r '.result.pane | [.tab_id // "", .workspace_id // ""]
          | join("\u001f")' <<<"$info" 2>/dev/null) || tab="" ws=""
      else
        printf 'dispatch: no agent in pane %s.\n' "$pane" >&2
        exit 1
      fi
      busy=""
      if [ "$view_focused" = true ]; then
        busy="looked at in the view $view"
      else
        case "$status" in idle | done | gone) break ;; esac
        busy="still ${status:-unknown}"
      fi
      poll=${DISPATCH_POLL:-30}
      if [ "$mode" != wait ]; then
        if [ "$view_focused" = true ]; then
          printf 'dispatch: the user looks at the view %s of pane %s. Close nothing.\n' "$view" "$pane" >&2
          exit 1
        fi
        left=$((deadline - SECONDS))
        if [ "$left" -le 0 ]; then
          printf 'dispatch: the worker in %s is %s. Close nothing.\n' "$pane" "$busy" >&2
          exit 1
        fi
        # Do not sleep past the deadline: the last check is at the deadline.
        [ "$poll" -le "$left" ] || poll=$left
      fi
      sleep "$poll"
    done
    label=$("${HW[@]}" workspace get "$ws" 2>/dev/null | jq -r '.result.workspace.label // empty' 2>/dev/null) || label=""
    if [[ "$label" != *" workers" ]]; then
      printf 'dispatch: pane %s is not in a workers workspace. Close nothing.\n' "$pane" >&2
      exit 1
    fi
    if [ -z "$tab" ]; then
      tab=$("${HW[@]}" pane get "$pane" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null) || tab=""
    fi
    if [ -z "$tab" ]; then
      printf 'dispatch: pane %s is gone.\n' "$pane" >&2
      exit 1
    fi
    count=$("${HW[@]}" tab get "$tab" 2>/dev/null | jq -r '.result.tab.pane_count // empty' 2>/dev/null) || count=""
    if [ "$count" != 1 ]; then
      printf 'dispatch: tab %s has %s panes, not only the worker. Close it by hand.\n' "$tab" "${count:-unknown}" >&2
      exit 1
    fi
    printf '%s\n' "$session"
    if ! "${HW[@]}" tab close "$tab" >/dev/null 2>&1; then
      printf 'dispatch: could not close tab %s.\n' "$tab" >&2
      exit 1
    fi
    # A view close failure is not a close failure: the worker is gone. Close the whole
    # view tab, also when the user split it: its other panes, such as a reviewr, belong
    # to the worker and have no use after it.
    if [ -n "$view_tab" ] && ! "$H" tab close "$view_tab" >/dev/null 2>&1; then
      printf 'dispatch: could not close the view %s.\n' "$view" >&2
    fi
    set_view "$pane"
    set_mark "$pane"
    set_worker "$pane"
    show_worker_count "${label% workers}"
    ;;
  workers)
    board="${2:-}"
    if [ -z "$board" ]; then
      printf 'usage: dispatch.sh workers BOARD\n' >&2
      exit 2
    fi
    if ! listing=$("${HW[@]}" workspace list 2>/dev/null) || ! agents=$("${HW[@]}" agent list 2>/dev/null); then
      printf 'dispatch: the hidden session %s does not run.\n' "$S" >&2
      exit 1
    fi
    show_worker_count "$board"
    ws=$(jq -r --arg l "$board workers" \
      '[.result.workspaces[]? | select(.label == $l)][0].workspace_id // empty' <<<"$listing")
    [ -n "$ws" ] || exit 0
    while IFS=$'\x1f' read -r pane name status seq; do
      mode="" report=""
      [ ! -f "$workers" ] ||
        IFS=$'\t' read -r mode report < <(awk -F '\t' -v p="$pane" \
          '$1 == p { m = $2; r = $4 } END { printf "%s\t%s\n", m, r }' "$workers")
      # A worker from before the workers file: the report path of its prompt, in its
      # transcript. The first match is the prompt of start.
      if [ -z "$report" ] &&
        session=$("${HW[@]}" agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_session.value // empty' 2>/dev/null) &&
        [ -n "$session" ]; then
        for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$session.jsonl"; do
          [ -f "$f" ] || continue
          report=$(grep -o -m 1 'write your report to [^ "\\]*\.md' "$f" | head -n 1) || report=""
          report=${report#write your report to }
          [ -z "$report" ] || break
        done
      fi
      if [ -z "$report" ] && [ -n "$name" ]; then
        # Else the newest report of its name. A name
        # with -N (a taken name) has the report of the name without it.
        for base in "$name" "${name%-[2-9]}"; do
          for f in "$state/$base"-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] || continue
            [ -n "$report" ] && [ ! "$f" -nt "$report" ] || report=$f
          done
          [ -z "$report" ] || break
        done
      fi
      exists=false first="" mtime=""
      if [ -n "$report" ] && [ -f "$report" ]; then
        exists=true
        first=$(head -n 1 "$report")
        # As date --iso-8601=seconds: the macOS date has no long options.
        mtime=$(file_mtime "$report")
        printf -v mtime '%(%Y-%m-%dT%H:%M:%S%z)T' "${mtime%%[.,]*}"
        mtime="${mtime:0:22}:${mtime:22}"
      fi
      view=$(view_of "$pane")
      [ -z "$view" ] || view_valid "$view" "$pane" || view=""
      # A live worker works or waits for its own job. Its report can be old: it never
      # waits for the user. A worker that is not live waits for the user when it is
      # blocked, or when its report is not a done result.
      job=false live=false waits=false
      case "$status" in
        working) live=true ;;
        blocked) waits=true ;;
        idle | done)
          if screen_job "$pane"; then
            job=true live=true
          else
            case "$first" in "RESULT: DONE"* | "STATUS: OK"*) ;; *) waits=true ;; esac
          fi
          ;;
      esac
      jq -cn --arg pane "$pane" --arg name "$name" --arg status "$status" --arg seq "$seq" \
        --arg mode "$mode" --arg report "$report" --argjson exists "$exists" --arg first "$first" \
        --arg mtime "$mtime" --arg view "$view" --argjson job "$job" --argjson live "$live" \
        --argjson waits "$waits" '
        def n: if . == "" then null else . end;
        {pane: $pane, name: ($name | n), status: ($status | n), seq: ($seq | n), mode: ($mode | n),
          report: ($report | n), report_exists: $exists, first_line: ($first | n),
          report_mtime: ($mtime | n), view: ($view | n), job: $job, live: $live, waits: $waits}'
    done < <(jq -r --arg ws "$ws" '.result.agents[]? | select(.workspace_id == $ws)
      | [.pane_id, .name // "", .agent_status // "", ((.completion_seq // .state_change_seq) // "" | tostring)]
      | join("\u001f")' <<<"$agents")
    ;;
  views-restore)
    # After a restart of Herdr, the view panes of the user come back as bare shells (the
    # attach is not restored) and the workers come back with their pane IDs. Close each
    # tab of an orchestrator workspace whose panes all show only the login shell, then
    # open the view of each live worker that has none. With --wait, repeat every
    # DISPATCH_RESTORE_POLL seconds (5) for DISPATCH_RESTORE_WAIT seconds (180) until
    # the hidden session, its agents and the orchestrators are back. Never fails.
    [ "$PANE_SESSION" != "$BOARD_SESSION" ] || exit 0
    [ -s "$workers" ] || exit 0
    deadline=$((SECONDS + ${DISPATCH_RESTORE_WAIT:-180}))
    while :; do
      rc=0
      restore_pass || rc=$?
      [ "$rc" -ne 0 ] || break
      [ "${2:-}" = --wait ] || break
      if [ "$SECONDS" -ge "$deadline" ]; then
        printf 'views-restore: gave up, a worker is not back.\n' >&2
        break
      fi
      sleep "${DISPATCH_RESTORE_POLL:-5}"
    done
    exit 0
    ;;
  restart-notice)
    # After a Herdr restart, an orchestrator claude resumes with its old context but its
    # background wait and watch commands are gone. Tell each running orchestrator of the
    # user once. Only startup.sh runs this. Return at once: a detached call for each
    # orchestrator waits until it is idle or done (DISPATCH_NOTICE_TIMEOUT_MS, 300000 by
    # default), because Herdr rejects a prompt to a blocked agent or to one that starts.
    [ "$PANE_SESSION" != "$BOARD_SESSION" ] || exit 0
    log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/board.log"
    if [ "${2:-}" = --one ]; then
      board="${3:?board}" orch="${4:?pane}"
      if ! "$H" agent wait "$orch" --until idle --until "done" --timeout "${DISPATCH_NOTICE_TIMEOUT_MS:-300000}" >/dev/null 2>&1; then
        printf 'restart-notice: the orchestrator of %s (%s) is not idle. No notice.\n' "$board" "$orch" >&2
        exit 0
      fi
      text="Herdr restarted, so your background wait and watch commands stopped. Run bash ~/.claude/skills/board-orchestrator/dispatch.sh workers $board, then handle each worker as in rules 6 and 7: record each new report (rule 7), and start wait or watch again for the others (rule 6)."
      if ! "$H" agent prompt "$orch" "$text" >/dev/null 2>&1; then
        printf 'restart-notice: the prompt to the orchestrator of %s (%s) failed.\n' "$board" "$orch" >&2
      fi
      exit 0
    fi
    while IFS= read -r -u 5 board; do
      [ -n "$board" ] || continue
      orch=$(orchestrator_pane "$board") || continue
      detach bash "$here/dispatch.sh" restart-notice --one "$board" "$orch" </dev/null >>"$log" 2>&1
    done 5< <(orchestrator_boards || true)
    exit 0
    ;;
  views-sync)
    # The hook of pane.closed and pane.exited: a closed reviewr leaves a view that is no
    # red with no reason to be an agent. A no-op when nothing changes. The hidden
    # session has no views.
    [ "$PANE_SESSION" != "$BOARD_SESSION" ] || exit 0
    [ -f "$views" ] || exit 0
    mkdir -p "$state"
    exec 9>>"$state/views-sync-$S.lock"
    flock -w 20 9 || exit 0
    while read -r -u 5 pane _; do
      sync_worker "$pane"
    done 5<"$views"
    ;;
  sync)
    pane="${2:?pane}"
    mkdir -p "$state"
    exec 9>>"$state/views-sync-$S.lock"
    flock -w 20 9 || exit 0
    sync_worker "$pane"
    ;;
  count-watch)
    # One listener for each hidden session: a second one has nothing to do.
    mkdir -p "$state"
    exec 8>>"$state/count-watch-$S.lock"
    # After a restart for new code, a child of the old listener can still hold the lock
    # for a moment: wait for it.
    if [ -n "${DISPATCH_COUNT_RESTART:-}" ]; then
      unset DISPATCH_COUNT_RESTART
      flock -w 5 8 || exit 0
    else
      flock -n 8 || exit 0
    fi
    # The listener runs for a long time: it must not keep old code after a git pull or
    # an edit. A file that is not older than this stamp makes a restart. On macOS the
    # dates have only seconds: a change in the second of the start then also makes a
    # restart, and that is safe. The test -nt is in bash 3.2 and with BSD tools.
    stamp="$state/count-watch-$S.stamp"
    touch "$stamp"
    fifo="$state/count-watch-$S.fifo"
    rm -f "$fifo"
    mkfifo "$fifo"
    trap 'rm -f "$fifo"' EXIT
    # A write to an nc that cannot connect must not stop the listener: see the printf.
    trap '' PIPE
    while :; do
      sock=$("$H" session list --json 2>/dev/null | jq -r --arg s "$S" \
        '[.sessions[]? | select(.name == $s and .running == true) | .socket_path // empty][0] // empty' 2>/dev/null) || sock=""
      [ -n "$sock" ] || exit 0
      # The session runs: a failed lookup is only for a moment.
      if ! listing=$("${HW[@]}" workspace list 2>/dev/null) || ! agents=$("${HW[@]}" agent list 2>/dev/null); then
        sleep 1
        continue
      fi
      # The workspace ID and the board of each workspace "<board> workers".
      boards=$(jq -r '.result.workspaces[]? | select((.label // "") | endswith(" workers"))
        | [.workspace_id, (.label | sub(" workers$"; ""))] | @tsv' <<<"$listing")
      panes=$(worker_panes "$boards" "$agents")
      request=$(jq -cn --arg p "$panes" '
        [$p | split("\n")[] | select(. != "") | {type: "pane.agent_status_changed", pane_id: .}] as $panes
        | {id: "count-watch", method: "events.subscribe", params: {subscriptions: ($panes
          + [{type: "pane.created"}, {type: "pane.closed"}, {type: "pane.exited"}, {type: "pane.agent_detected"}])}}')
      # The fifo is the stdin of nc. The listener keeps its write end open: nc can close
      # the connection at the end of its input. nc must not keep the lock.
      exec 6< <(exec "${DISPATCH_NC:-nc}" -U "$sock" <"$fifo" 2>/dev/null 8>&-)
      # bash before 4.4 does not set $! for a process substitution.
      nc_pid=${!:-}
      exec 7>"$fifo"
      if ! printf '%s\n' "$request" >&7 2>/dev/null; then
        # nc closed the connection at once: as no reply.
        exec 6<&- 7>&-
        exit 1
      fi
      started="" again="" pause=""
      while IFS= read -r line <&6; do
        if ! [ "$stamp" -nt "$here/dispatch.sh" ] || ! [ "$stamp" -nt "$here/lib.sh" ]; then
          [ -z "$nc_pid" ] || kill "$nc_pid" 2>/dev/null || true
          exec 6<&- 7>&- 8>&-
          rm -f "$fifo"
          # The new stamp must be in a later second than the change, else the new
          # listener restarts again.
          sleep 1
          DISPATCH_COUNT_RESTART=1 exec "$BASH" "$here/dispatch.sh" count-watch
        fi
        # A tab is white space for read: an empty first field would go. Use \x1f.
        IFS=$'\x1f' read -r event ws pane < <(jq -r '[.event // (if .error then "error" else "" end),
          .data.workspace_id // .result.type // "", .data.pane_id // ""] | join("\u001f")' <<<"$line" 2>/dev/null) ||
          continue
        case "$event" in
          "")
            [ "$ws" = subscription_started ] || continue
            started=1
            # A worker that came before the server recorded the subscription has no
            # status subscription and no pane event: compare the panes again.
            if agents=$("${HW[@]}" agent list 2>/dev/null) && [ "$(worker_panes "$boards" "$agents")" != "$panes" ]; then
              again=1
              break
            fi
            # Show the counts now: a change before the subscription has no event. Herdr
            # closes the workspace "<board> workers" with its last worker, so also count
            # each board with a workspace "<board> orchestrator" of the user: it then shows
            # 0 workers.
            # Copy the state of each worker to its view, and release the view of a
            # worker that is gone: a change before the subscription has no event.
            if [ -f "$views" ]; then
              while read -r -u 5 pane _; do
                if grep -qxF "$pane" <<<"$panes"; then
                  IFS=$'\x1f' read -r status cseq < <(jq -r --arg p "$pane" '[.result.agents[]? | select(.pane_id == $p)][0]
                    | [.agent_status // "", (.completion_seq // "" | tostring)] | join("\u001f")' <<<"$agents" 2>/dev/null) ||
                    status="" cseq=""
                  sync_view "$pane" "$status" "$cseq"
                else
                  release_view "$pane"
                fi
              done 5<"$views"
            fi
            user=$("$H" workspace list 2>/dev/null) || user='{}'
            while IFS= read -r board; do
              [ -z "$board" ] || show_worker_count "$board"
            done < <(jq -rn --argjson h "$listing" --argjson u "$user" '[($h.result.workspaces[]? | (.label // "")
              | select(endswith(" workers")) | sub(" workers$"; "")), ($u.result.workspaces[]? | (.label // "")
              | sub(" · .*$"; "") | select(endswith(" orchestrator")) | sub(" orchestrator$"; ""))] | unique[]')
            ;;
          error)
            # The server refused the subscription: try again after a pause.
            again=1 pause=1
            break
            ;;
          pane.agent_status_changed)
            board=$(awk -F '\t' -v w="$ws" '$1 == w { print $2 }' <<<"$boards")
            [ -z "$board" ] || show_worker_count "$board"
            # Copy the new status to the view. The completion seq tells if a red view
            # stays red: read it from the agent.
            if [ -n "$pane" ] && [ -n "$(view_of "$pane")" ] && agent=$("${HW[@]}" agent get "$pane" 2>/dev/null); then
              IFS=$'\x1f' read -r status cseq < <(jq -r '.result.agent
                | [.agent_status // "", (.completion_seq // "" | tostring)] | join("\u001f")' <<<"$agent" 2>/dev/null) ||
                status="" cseq=""
              sync_view "$pane" "$status" "$cseq"
            fi
            ;;
          *)
            # Status events need a pane ID: subscribe again with the new set of panes.
            again=1
            break
            ;;
        esac
      done
      # nc still runs only when the listener stopped the read.
      [ -z "$again" ] || [ -z "$nc_pid" ] || kill "$nc_pid" 2>/dev/null || true
      exec 6<&- 7>&-
      [ -z "$nc_pid" ] || wait "$nc_pid" 2>/dev/null || true
      if [ -n "$again" ]; then
        [ -z "$pause" ] || sleep 1
        continue
      fi
      # With no reply, the socket does not work: a retry does not help.
      [ -n "$started" ] || exit 1
      sleep 1
    done
    ;;
  report)
    file="${2:-}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
      printf 'usage: dispatch.sh report PATH\n' >&2
      exit 2
    fi
    # The orchestrator reads this, not the full report: a full report fills its context.
    awk -v path="$file" -v max=60 '
      function keep(name, text) {
        n[name]++
        if (n[name] <= max) buf[name] = buf[name] text "\n"
      }
      function out(name) {
        printf "%s", buf[name]
        if (n[name] > max) printf "[section cut: %d more lines]\n", n[name] - max
      }
      NR == 1 { first = $0 }
      NR <= 40 { head = head $0 "\n" }
      /^## / {
        sec = ""
        if ($0 ~ /^## Result[ \t\r]*$/) { sec = "result"; seen = 1 }
        else if ($0 ~ /^## Vault changes[ \t\r]*$/) sec = "vault"
      }
      sec != "" { keep(sec, $0); next }
      NR > 1 && /^REFUSED:/ { refused = refused $0 "\n" }
      END {
        if (seen) { print first; out("result"); out("vault"); printf "%s", refused }
        else printf "%s", head
        printf "full report: %s (%d lines)\n", path, NR
      }' "$file"
    ;;
  run-add)
    rel="${2:-}" file="${3:-}"
    if [ -z "$rel" ] || [ -z "$file" ] || [ ! -f "$file" ]; then
      printf 'usage: dispatch.sh run-add NOTE REPORT\n' >&2
      exit 2
    fi
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    note="$vault/$rel"
    if [ ! -f "$note" ]; then
      printf 'dispatch: no task note %s in the vault.\n' "$rel" >&2
      exit 1
    fi
    day=$(date +%F)
    # The script copies the full report, so that the report text does not go through the
    # orchestrator context. The report files are on one host only, the vault is on all.
    tmp=$(mktemp "$(dirname "$note")/.run-add.XXXXXX")
    awk -v day="$day" '
      # The report: demote its headings by 3 levels to put them under the day line.
      # A "#" line in a code block is not a heading.
      FILENAME == ARGV[1] {
        if ($0 ~ /^[ \t]*(```|~~~)/) fence = !fence
        if (!fence && $0 ~ /^#+ /) $0 = "###" $0
        rep[++nr] = $0
        next
      }
      { line[++n] = $0 }
      END {
        while (nr > 0 && rep[nr] ~ /^[ \t\r]*$/) nr--
        i = 1
        if (line[1] == "---") {
          for (i = 2; i <= n && line[i] != "---"; i++)
            if (line[i] ~ /^updated:/) line[i] = "updated: " day
          i++
        }
        # Find ## Runs, its end, and the entry of today in it. A record of the same card
        # again on the same day (after a watch exit 0) replaces that entry. A "#" line in a
        # code block of an old run is not a heading.
        for (; i <= n; i++) {
          if (line[i] ~ /^[ \t]*(```|~~~)/) { nfence = !nfence; continue }
          if (nfence) continue
          if (runs && line[i] ~ /^## /) { end = i; break }
          if (line[i] ~ /^## Runs[ \t\r]*$/) runs = i
          if (runs && line[i] ~ /^### /) {
            if (from && !to) to = i
            if (line[i] ~ ("^### " day "[ \t\r]*$")) { from = i; to = 0 }
          }
        }
        if (!end) end = n + 1
        if (from && !to) to = end
        # The new run replaces the lines cut to rest - 1.
        if (from) { cut = from; rest = to }
        else { cut = end; rest = end }
        last = cut - 1
        while (last > 0 && line[last] ~ /^[ \t\r]*$/) last--
        for (k = 1; k <= last; k++) print line[k]
        if (last) print ""
        if (!runs) { print "## Runs"; print "" }
        print "### " day
        print ""
        for (k = 1; k <= nr; k++) print rep[k]
        while (rest <= n && line[rest] ~ /^[ \t\r]*$/) rest++
        if (rest <= n) print ""
        for (k = rest; k <= n; k++) print line[k]
      }' "$file" "$note" >"$tmp"
    mv "$tmp" "$note"
    printf 'run-add: %s %s\n' "$rel" "$day"
    ;;
  note-add)
    rel="${2:-}" board="${3:-}" at="${4:-}" title="${5:-}"
    if [ -z "$rel" ] || [ -z "$board" ] || [[ ! "$at" =~ ^[1-9][0-9]*$ ]] || [ -z "$title" ]; then
      printf 'usage: dispatch.sh note-add NOTE BOARD LINE TITLE\n' >&2
      exit 2
    fi
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    note="$vault/$rel" file="$vault/Boards/$board.md"
    if [ ! -f "$note" ]; then
      printf 'dispatch: no task note %s in the vault.\n' "$rel" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      printf 'dispatch: no board %s in the vault.\n' "$board" >&2
      exit 1
    fi
    # The script copies the card text, so that the long text does not go through the
    # orchestrator context. The line number comes from a scan just before: the user can
    # edit the board in between, so the card TITLE must still be at that line.
    text=$(awk -v at="$at" '
      NR < at { next }
      NR == at { if ($0 !~ /^- \[.\] /) exit 3; card = $0; next }
      /^\t/ { sub(/^\t/, ""); ctx = ctx (ctx == "" ? "" : "\n") $0; card = card "\n" $0; next }
      { exit }
      END { if (card == "") exit 3; print card; if (ctx == "") exit 4; print "\x1e"; print ctx }' "$file") && rc=0 || rc=$?
    # The title is the text between the first ** and the next **, as in board-scan.sh.
    first=${text%%$'\n'*} found=""
    if [ "$rc" -ne 3 ] && [[ "$first" == *'**'*'**'* ]]; then
      found=${first#*\*\*} found=${found%%\*\**}
    fi
    if [ "$rc" -eq 3 ] || [ "$found" != "$title" ]; then
      printf 'dispatch: no card %s at line %s of Boards/%s.md.\n' "$title" "$at" "$board" >&2
      exit 1
    fi
    case $rc in
      0) ;;
      *)
        printf 'dispatch: the card at line %s of Boards/%s.md has no context line.\n' "$at" "$board" >&2
        exit 1
        ;;
    esac
    card=${text%%$'\n\x1e\n'*} ctx=${text#*$'\n\x1e\n'}
    # A card can also link related task notes. A card with no task link is new: the
    # orchestrator made its note just before.
    links=$(grep -o '\[\[Tasks/[^]|#]*' <<<"$card" | cut -c3- || true)
    if [ -n "$links" ] && ! grep -qxF "${rel%.md}" <<<"$links"; then
      printf 'dispatch: the card at line %s of Boards/%s.md links %s, not %s.\n' "$at" "$board" "${links%%$'\n'*}" "$rel" >&2
      exit 1
    fi
    day=$(date +%F)
    tmp=$(mktemp "$(dirname "$note")/.note-add.XXXXXX")
    # awk -v would read the backslashes of the text as escapes: ENVIRON keeps them.
    NOTE_TEXT="$ctx" awk -v day="$day" '
      BEGIN {
        na = split(ENVIRON["NOTE_TEXT"], add, "\n")
        # Put each heading of the text under the ### entry. A "#" line in a code block is
        # not a heading.
        for (k = 1; k <= na; k++) {
          if (add[k] ~ /^[ \t]*(```|~~~)/) tfence = !tfence
          else if (!tfence && add[k] ~ /^#+ /) add[k] = "###" add[k]
        }
      }
      { line[++n] = $0 }
      END {
        i = 1
        if (line[1] == "---") {
          for (i = 2; i <= n && line[i] != "---"; i++)
            if (line[i] ~ /^updated:/) line[i] = "updated: " day
          i++
        }
        # Find ## Notes and its end. A "#" line in a code block is not a heading.
        for (; i <= n; i++) {
          if (line[i] ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
          if (fence) continue
          if (notes && line[i] ~ /^## /) { end = i; break }
          if (line[i] ~ /^## Notes[ \t\r]*$/) notes = i
        }
        if (!end) end = n + 1
        last = end - 1
        while (last > 0 && line[last] ~ /^[ \t\r]*$/) last--
        for (k = 1; k <= last; k++) print line[k]
        if (last) print ""
        if (!notes) { print "## Notes"; print "" }
        print "### " day ", from the board"
        print ""
        for (k = 1; k <= na; k++) print add[k]
        rest = end
        while (rest <= n && line[rest] ~ /^[ \t\r]*$/) rest++
        if (rest <= n) print ""
        for (k = rest; k <= n; k++) print line[k]
      }' "$note" >"$tmp"
    mv "$tmp" "$note"
    printf 'note-add: %s %s\n' "$rel" "$day"
    ;;
  log)
    board="${2:-}" file="${3:-}"
    if [ -z "$board" ] || [ -z "$file" ]; then
      printf 'usage: dispatch.sh log BOARD FILE\n' >&2
      exit 2
    fi
    if [ ! -s "$file" ]; then
      printf 'dispatch: the log file %s is missing or empty.\n' "$file" >&2
      exit 2
    fi
    # The log has one line for each card: a line end in the text becomes a space.
    text=$(tr '\n' ' ' <"$file")
    text="${text% }"
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    day=$(date +%F)
    name="$day - $board (board orchestrator)"
    note="$vault/Dev Logs/$name.md"
    if [ ! -f "$note" ]; then
      mkdir -p "$vault/Dev Logs"
      cat >"$note" <<NOTE
---
date: $day
type: devlog
board: "[[Boards/$board]]"
tags: [devlog, board-orchestrator, $board]
ai-first: true
---

## For future agent
This note is the work log of the board orchestrator of [[Boards/$board]] for $day. Each line under Log is the result of one card: the time, the card title, the result, the links and the report path. The orchestrator writes a line when it records a card on the board. For the details of a card, read its report.

## Log
NOTE
    fi
    # Log is the last section of the note: a new line goes at the end.
    printf -- '- %s %s\n' "$(date +%H:%M)" "$text" >>"$note"
    daily="$vault/Daily/$day.md"
    if [ -f "$daily" ] && ! grep -qF "[[Dev Logs/$name" "$daily"; then
      # The temp file is in the same folder, so that mv replaces the note in one step.
      tmp=$(mktemp "$vault/Daily/.$day.XXXXXX")
      # Put the link after the last line that is not blank in the Work section, else
      # at the end of the note.
      awk -v link="- [[Dev Logs/$name]]" '
        { line[NR] = $0 }
        /^## / { work = ($0 ~ /^## Work[ \t\r]*$/); if (work) at = NR }
        work && $0 !~ /^[ \t\r]*$/ { at = NR }
        END {
          if (!at) at = NR
          for (i = 1; i <= NR; i++) { print line[i]; if (i == at) print link }
        }' "$daily" >"$tmp"
      mv "$tmp" "$daily"
    fi
    ;;
  inbox-clear)
    rel="${2:-}"
    # One path part after _inbox/, no dot file: the command cannot reach a note out of
    # the inbox or a Syncthing temp file.
    if ! [[ "$rel" =~ ^_inbox/[^/.][^/]*\.md$ ]]; then
      printf 'usage: dispatch.sh inbox-clear _inbox/NAME.md\n' >&2
      exit 2
    fi
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    if [ ! -f "$vault/$rel" ]; then
      printf 'dispatch: %s is gone from the vault.\n' "$rel" >&2
      exit 1
    fi
    rm -- "$vault/$rel"
    printf 'inbox-clear: %s\n' "$rel"
    ;;
  *)
    printf 'usage: dispatch.sh policy|policy-set|start|wait|last|watch|remind|answer|notify|show|close|workers|report|run-add|note-add|log|inbox-clear|views-sync|views-restore|restart-notice|sync|count-watch ...\n' >&2
    exit 2
    ;;
esac
