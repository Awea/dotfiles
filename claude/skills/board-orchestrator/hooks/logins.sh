#!/usr/bin/env bash
# SessionStart hook (startup, resume) of a board task worker: check the MCP and database
# logins of the board with board-ro check. On a failure, show it to the user in the pane
# and tell the worker. When all logins work, or outside a board, print nothing. Exit 0
# always: a failed check never stops the worker. Argument auto: an automatic worker, which
# runs with no user.
set -uo pipefail
mode=${1:-task}
cat >/dev/null
if command -v board-ro >/dev/null 2>&1; then
  lines=$(board-ro check 2>&1)
  code=$?
else
  lines='board-ro: not on PATH. Fix: add the board-resources bin folder to PATH.'
  code=1
fi
[ "$code" -eq 1 ] || exit 0
text="The start check of the board logins found these failures:
$lines
In your first reply, tell the user each failure and its fix, one line each. Then do the work that does not need these logins. When the work needs one, ask the user to fix it and end your turn."
if [ "$mode" = auto ]; then
  text="The start check of the board logins found these failures:
$lines
You run with no user: do not wait for one. Do the work that does not need these logins. When the work needs one, stop and write your report with STATUS: STOP, and one line for each login that you need, with its fix."
fi
jq -n --arg m "Board logins fail:
$lines" --arg t "$text" \
  '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $t}}'
exit 0
