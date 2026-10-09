#!/usr/bin/env bash
# UserPromptSubmit hook for the ste-writing skill. Two jobs:
#
#   1. Put the rule card into context on every turn, so the discipline does not
#      depend on the model remembering to load the skill.
#   2. Show the score of the last reply, when the Stop hook wrote a warning
#      instead of blocking. That is the feedback path that costs no second copy
#      of the reply on screen.
#
# Canonical copy: the ep01 kit, ste-writing/hooks/ste-inject.sh
set -euo pipefail

PAYLOAD="$(cat)"
SESSION="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "none"')"
KEY="$(printf '%s' "$SESSION" | shasum | cut -c1-16)"
WARN="$HOME/.claude/ste-gate/${KEY}.warn.json"

emit_card() {
  cat <<'EOF'
<ste-writing-standing-rule>
ASD-STE100 governs all prose the reader sees: replies, commits, docs, comments,
PR text, trackers. Never code or command syntax. Default: STE-flavored. Strict
for runbooks, procedures, error messages, safety text.
Words: active voice, simple tenses, keep the articles. No contractions,
semicolons, phrasal verbs or marketing adjectives. 20 words max for an
instruction, 25 otherwise. Short common words. One name for one thing. A verb
for an action. Noun stacks of three words max.
Shape (the reader has ADHD): lead with the action. Number steps, one action
each, five max. No preamble, recap or closer. State step N of M. Estimates in
minutes, hours or days. One issue at a time. Cut a hedge that carries no fact.
Full rules: load the ste-writing skill.
</ste-writing-standing-rule>
EOF
}

emit_feedback() {
  [ -f "$WARN" ] || return 0
  printf '\n'
  jq -r '
    "<ste-writing-feedback>",
    "Your last reply scored \(.score) violations per 100 words. The target is \(.limit).",
    (if (.top | length) > 0 then "Worst Layer 1 categories: \(.top | join(", "))." else empty end),
    (if .shape_total > 0 then "Layer 2 shape hits: \(.shape_total) (\(.shape_top | join(", ")))." else empty end),
    "Longest sentence: \(.longest_sentence_words) words.",
    "Fix those categories in this reply.",
    "</ste-writing-feedback>"
  ' "$WARN" 2>/dev/null || true
  rm -f "$WARN"
}

{ emit_card; emit_feedback; } |
  jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.},suppressOutput:true}'
