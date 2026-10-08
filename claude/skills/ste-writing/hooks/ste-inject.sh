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
ASD-STE100 governs every word the reader sees in this reply, and in any prose
you write to a file: chat text, commit messages, docs, code comments, PR text,
error messages, task trackers, wiki pages. It never applies to code,
identifiers, or command syntax. Default mode: STE-flavored. Use strict mode for
runbooks, procedures, error messages, and safety text.

LAYER 1 - the words
- Active voice. Simple tenses only. No present perfect, no stacked modals.
- One instruction per sentence. Max 20 words for an instruction, 25 otherwise.
- No contractions. No semicolons. Keep the articles.
- Short common words: use, start, make sure, do, give, show, before, about.
- No phrasal verbs: spin up, dive into, kick off, roll out, reach out.
- No marketing adjectives: seamless, robust, powerful, effortless, elegant.
- One name for one thing. Do not rotate synonyms for the same action.
- Use a verb for an action. Write "analyze the log", not "perform an analysis".
- Multi-word nouns: three words maximum.

LAYER 2 - the shape (a reply to a person, a task, a PR description)
- The reader has ADHD. Lead with the action, the command, or the path.
- Number a multi-step task. One bounded action for each step.
- No preamble, no recap, no closer. Start with the answer, stop when it is done.
- Cap an action list at five items. A reference table has no cap.
- Restate the state each turn: step N of M, what is done, what is next.
- Give an estimate in minutes, hours, or days. Never "a while".
- Show what now works, in concrete terms. Stay matter-of-fact about an error.
- Finish one issue. Offer the second one as a separate question.
- Cut a hedge that carries no fact. Keep a qualifier that bounds a claim.

Lint the draft BEFORE you send it. A Stop hook lints it after, and a block puts
a second copy of the same answer on the reader's screen:
  python3 ~/.claude/skills/ste-writing/ste-lint.py --fail-over 2.5 FILE
Full rules, both modes, and the four layer conflicts: load the ste-writing skill.
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
    "Lint the draft of this reply before you send it.",
    "</ste-writing-feedback>"
  ' "$WARN" 2>/dev/null || true
  rm -f "$WARN"
}

{ emit_card; emit_feedback; } |
  jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.},suppressOutput:true}'
