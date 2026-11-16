#!/usr/bin/env bash
# PreToolUse hook (Bash) of the board orchestrator on herdr-app. A worker of a board
# must not change the herdr-app window: the user sees only what the orchestrator shows.
# A worker can start other agents (a subagent, or a claude in an hc terminal), for
# example for an independent review: an hc child shows under the worker in the agents
# list. Exit 2 blocks the call.
set -uo pipefail
# Not an hc terminal: nothing to guard. Decide only on hc, never on HERDR_*: an hc core
# started from Herdr 0.9.5 gives its terminals that environment.
[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$(readlink -f "$0")")/../lib.sh"
labels=$(hc_labels "$HC_TERMINAL_ID") || exit 0
[ "$(jq -r '.["board.role"] // empty' <<<"$labels")" = worker ] || exit 0

command=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$command" ] || exit 0

block() {
  printf 'board-orchestrator: a board worker cannot %s. Write it in the report: the orchestrator does it.\n' "$1" >&2
  exit 2
}

# Each part of the command between ; & | and newlines.
while IFS= read -r part; do
  read -ra words <<<"$part"
  for ((i = 0; i < ${#words[@]}; i++)); do
    if [ "${words[$i]}" = herdr-app ] && [ "${words[$((i + 1))]:-}" = "do" ]; then
      block "change the herdr-app window (herdr-app do)"
    fi
  done
done < <(tr ';&|' '\n' <<<"$command")
exit 0
