#!/usr/bin/env bash
# SessionStart hook (compact) of the board orchestrator and its workers on Renux. A compact
# removes the text of the skill from the orchestrator, and the first prompt (the card and
# the rules) from a worker: tell each one to read it again.
set -uo pipefail
# The board, the role and the session are in the env of the pane.
[ -n "${REX_BLOCK:-}" ] || exit 0
board=${BOARD:-}
[ -n "$board" ] || exit 0
case "${BOARD_ROLE:-}" in
  orchestrator)
    text="You are the orchestrator of the board $board. The compact removed the text of the board-orchestrator skill. Before any other action, read ~/.claude/skills/board-orchestrator/SKILL.md with the Read tool and follow it, with \"$board\" as the whole argument text. Do not start again at rule 1: continue the work of the summary with the rules of the skill. Where the summary and the skill do not agree, the skill wins, for example on what you write to the user."
    ;;
  worker)
    # shellcheck source=SCRIPTDIR/../lib.sh
    source "$(dirname "$(readlink -f "$0")")/../lib.sh"
    # dispatch.sh start keeps the prompt. A worker from before that has no file.
    f=$(prompt_path "${BOARD_SESSION:-}") && [ -f "$f" ] || exit 0
    text="You are a worker of the board $board. The compact removed your first prompt: the card, the exact words of the user, the rules and the path and form of your report. Before any other action, read $f with the Read tool and follow it. Do not start the card again: continue the work of the summary with the rules of that file. Where the summary and the file do not agree, the file wins, with one exception: a request or a decision of the user after the first prompt wins over the file."
    ;;
  *) exit 0 ;;
esac
jq -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $t}}'
exit 0
