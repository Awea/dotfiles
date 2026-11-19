#!/usr/bin/env bash
# PreToolUse hook (Agent): a review runs with the reviewer subagent type. The reviewer
# file (claude/agents/reviewer.md) sets the model, the effort and the tools of a review.
# A general-purpose or fork agent with a superpowers review template does not load it.
#
# A call is a review when its subagent type ends in code-reviewer, when its description
# starts with "review" or "re-review", or, for a type other than Explore, when its
# description has the word "review" and no fix word (fix, apply, address, resolve...):
# "Fix review of task 3" is a fix, and "Find how the review flow works" is a search.
# "reviewer" and "reviewr" are not the word "review".
# Exit 2 refuses the call and tells the model to use the reviewer type.
# Runs on Linux and macOS (bash 3.2, POSIX grep -E).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || exit 0
case "$tool" in Agent | Task) ;; *) exit 0 ;; esac
type=$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$input")
[ "$type" = reviewer ] && exit 0
case "$type" in *code-reviewer) review=1 ;; *) review="" ;; esac
description=$(jq -r '.tool_input.description // ""' <<<"$input" | tr '[:upper:]' '[:lower:]')

word='(^|[^[:alnum:]])'
end='([^[:alnum:]]|$)'
fixes='fix|fixes|fixing|fixed|apply|applying|address|addressing|implement|rebase|resolve|resolves|resolving|handle|handling|respond|responding'
if [ -n "$review" ] || printf '%s\n' "$description" | grep -Eq "^[^[:alnum:]]*(re-?)?review(s|ing)?$end"; then
  :
elif [ "$type" != Explore ] && printf '%s\n' "$description" | grep -Eq "${word}(re-?)?review(s|ing)?$end" &&
  ! printf '%s\n' "$description" | grep -Eq "${word}($fixes)$end"; then
  :
else
  exit 0
fi

printf 'review-agent-type: run a review with subagent_type "reviewer", not "%s". The reviewer file sets the model, the effort and the tools. Give it the commit range and the goal. When the task is not a code review, write the description without the word review.\n' "$type" >&2
exit 2
