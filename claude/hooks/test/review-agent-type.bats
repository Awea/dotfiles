#!/usr/bin/env bats
# Tests for claude/hooks/review-agent-type.sh.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/hooks/test/

SCRIPT="$BATS_TEST_DIRNAME/../review-agent-type.sh"

# agent DESCRIPTION [TYPE]: run the hook on an Agent call. With no TYPE, the call has
# no subagent_type, as a general-purpose call.
agent() {
  local json
  json=$(jq -cn --arg d "$1" --arg t "${2:-}" \
    '{tool_name: "Agent", tool_input: ({description: $d, prompt: "x"}
      + (if $t == "" then {} else {subagent_type: $t} end))}')
  run bash "$SCRIPT" <<<"$json"
}

@test "refuses a review with another subagent type" {
  for d in 'Review Task 1 (spec + quality)' 'Re-review Task 3 fix round 1' 'Whole-branch review before push' \
    'Final whole-branch review' 'Review #1006 fix diff' 'Rereview the fix wave' 'Pass-2 review indexer-3'; do
    for t in general-purpose fork ''; do
      agent "$d" "$t"
      [ "$status" -eq 2 ] || { echo "not refused: $t: $d"; return 1; }
      [[ "$output" == *"subagent_type"*"reviewer"* ]]
    done
  done
  for d in 'Review Task 1 (spec + quality)' 'Re-review Task 3 fix round 1'; do
    agent "$d" Explore
    [ "$status" -eq 2 ] || { echo "not refused: Explore: $d"; return 1; }
  done
}

@test "allows a review with the reviewer subagent type" {
  agent 'Review Task 1 (spec + quality)' reviewer
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows a call that is not a review" {
  for d in 'Implement Task 2' 'Fix review of tasks 3-4' 'Apply five minor review fixes' 'Final review fix wave #980' \
    'Rebase 1211 and apply review style' 'Find reviewr launch settings' 'Report worker views as agents' \
    'Audit branch for Linux-only calls' 'Address the reviewer findings' 'Addressing review findings' \
    'Fixing review comments' 'Resolve review comments' 'Handle review feedback' 'Respond to review'; do
    agent "$d" general-purpose
    [ "$status" -eq 0 ] || { echo "refused: $d"; return 1; }
  done
}

@test "allows a search that names the review, and refuses a code-reviewer type" {
  agent 'Find how the review flow works' Explore
  [ "$status" -eq 0 ]
  agent 'Find how the review flow works' general-purpose
  [ "$status" -eq 2 ]
  agent 'Code quality check Task 3' superpowers:code-reviewer
  [ "$status" -eq 2 ]
}

@test "ignores another tool" {
  run bash "$SCRIPT" <<<'{"tool_name":"Bash","tool_input":{"command":"echo review"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
