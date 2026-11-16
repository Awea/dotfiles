#!/usr/bin/env bash
# SessionStart hook (compact) of the board orchestrator on herdr-app. A compact removes
# the text of the skill: tell the orchestrator to read it again.
set -uo pipefail
# Decide only on hc, never on HERDR_* (see guard.sh).
[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$(readlink -f "$0")")/../lib.sh"
labels=$(hc_labels "$HC_TERMINAL_ID") || exit 0
[ "$(jq -r '.["board.role"] // empty' <<<"$labels")" = orchestrator ] || exit 0
board=$(jq -r '.board // empty' <<<"$labels")
[ -n "$board" ] || exit 0
text="You are the orchestrator of the board $board. The compact removed the text of the board-orchestrator skill. Before any other action, read ~/.claude/skills/board-orchestrator/SKILL.md with the Read tool and follow it, with \"$board\" as the whole argument text. Do not start again at rule 1: continue the work of the summary with the rules of the skill. Where the summary and the skill do not agree, the skill wins, for example on what you write to the user."
jq -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $t}}'
exit 0
