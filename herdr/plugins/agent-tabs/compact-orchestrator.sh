#!/usr/bin/env bash
# Claude Code hook (SessionStart, matcher compact): a compact removes the text of the
# board-orchestrator skill, and Claude Code does not attach it again. The orchestrator
# then follows only the summary, which keeps a short and wrong form of the rules (for
# example "relay the question of the worker"). For the claude of an orchestrator, tell
# it to read the skill again before it acts.
#
# An orchestrator claude runs in the session of the user, in the workspace
# "<board> orchestrator" (or "<board> orchestrator · 2 workers" from an old version). Its
# agent name is the agent slug of "<board>-orchestrator" (see agent_slug in lib.sh), or
# that slug with a number added. Another claude gets no
# text, also each claude of the hidden session of the workers (DISPATCH_SESSION,
# board-workers by default).
#
# `make links` links the script as ~/.claude/hooks/herdr-compact-orchestrator.sh.
#
# The hook never stops claude: it always exits 0.
set -uo pipefail
[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] || exit 0
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$(dirname "$(readlink -f "$0")")/lib.sh"
[ "$PANE_SESSION" != "$BOARD_SESSION" ] || exit 0
board=$("$H" workspace list 2>/dev/null | jq -r --arg w "$HERDR_WORKSPACE_ID" '
  .result.workspaces[]? | select(.workspace_id == $w) | .label // "" | sub(" · .*$"; "")
  | select(endswith(" orchestrator")) | sub(" orchestrator$"; "")' 2>/dev/null) || exit 0
[ -n "$board" ] || exit 0
name=$("$H" agent get "${HERDR_PANE_ID:-}" 2>/dev/null | jq -r '.result.agent.name // ""' 2>/dev/null) || exit 0
slug=$(agent_slug "$board-orchestrator")
n=${name#"$slug-"}
[ "$name" = "$slug" ] || { [ "$n" != "$name" ] && [[ "$n" =~ ^[0-9]+$ ]]; } || exit 0
text="You are the orchestrator of the board $board. The compact removed the text of the board-orchestrator skill. Before any other action, read ~/.claude/skills/board-orchestrator/SKILL.md with the Read tool and follow it, with $board as the first word of the arguments. Do not start again at rule 1: continue the work of the summary with the rules of the skill. Where the summary and the skill do not agree, the skill wins, for example on what you write to the user."
jq -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $t}}'
exit 0
