#!/usr/bin/env bats
# SKILL.md of board-orchestrator.

bats_require_minimum_version 1.5.0
load helper

# The skill text: SKILL.md and the parts that it tells the orchestrator to read.
parts() { printf '%s\n' "$SKILL_DIR/SKILL.md" "$SKILL_DIR/start.md" "$SKILL_DIR/shorten.md"; }

@test "skill names only dispatch commands that exist" {
  [ -f "$SKILL_DIR/SKILL.md" ]
  for c in $(parts | xargs grep -h -o -E 'dispatch\.sh [a-z-]+' | awk '{print $2}' | sort -u); do
    grep -q -E "^  ([a-z|-]+\|)?$c(\|[a-z|-]+)?\)$" "$SKILL_DIR/dispatch.sh" || { echo "missing: $c"; return 1; }
  done
}

@test "skill has no Herdr 0.9.5 words" {
  [ -f "$SKILL_DIR/SKILL.md" ]
  # Not "! grep": bats ignores a negated command that is not the last one.
  run grep -n -i -E 'dispatch\.sh (wait|watch|show|notify|views)|herdr\.invalid|ctrl\+b|view tab|herdr notification|hidden session|pane link' $(parts)
  [ "$status" -eq 1 ]
}

@test "skill uses its own paths" {
  [ -f "$SKILL_DIR/SKILL.md" ]
  # Not "! grep": bats ignores a negated command that is not the last one.
  run grep -n 'skills/board-orchestrator-hc/' $(parts)
  [ "$status" -ne 0 ]
  grep -q '~/.claude/skills/board-orchestrator/dispatch.sh' "$SKILL_DIR/SKILL.md"
}

@test "skill gives the hc note texts" {
  grep -q 'report <slug> <path>' "$SKILL_DIR/SKILL.md"
  grep -q 'is blocked (' "$SKILL_DIR/SKILL.md"
  grep -q 'exited (exit' "$SKILL_DIR/SKILL.md"
  grep -q 'close <slug></hc>' "$SKILL_DIR/SKILL.md"
}

@test "skill has its own name" {
  grep -qx 'name: board-orchestrator' "$SKILL_DIR/SKILL.md"
}

@test "skill takes the whole argument text as BOARD" {
  grep -q 'BOARD is the whole argument text' "$SKILL_DIR/SKILL.md"
  ! grep -q 'The first word is BOARD' "$SKILL_DIR/SKILL.md"
}

@test "skill parts exist, and the core tells when to read each" {
  for part in start.md shorten.md; do
    [ -f "$SKILL_DIR/$part" ]
    grep -q "~/.claude/skills/board-orchestrator/$part" "$SKILL_DIR/SKILL.md"
  done
}

@test "each rule is in one part: rules 1 to 4 at the start, 9 to shorten, the rest in the core" {
  for n in 1 2 3 4; do grep -q -E "^$n\. \*\*" "$SKILL_DIR/start.md"; done
  for n in 5 6 7 8; do grep -q -E "^$n\. \*\*" "$SKILL_DIR/SKILL.md"; done
  grep -q -E '^9\. \*\*' "$SKILL_DIR/shorten.md"
  for n in 1 2 3 4 5 6 7 8 9; do
    [ "$(parts | xargs cat | grep -c -E "^$n\. \*\*")" -eq 1 ] || { echo "rule $n"; return 1; }
  done
}

@test "the core that a compact reads again is at most 33000 bytes" {
  size=$(wc -c <"$SKILL_DIR/SKILL.md")
  echo "SKILL.md: $size bytes"
  [ "$size" -le 33000 ]
}

@test "the parts are not skills: no frontmatter" {
  for part in start.md shorten.md; do
    run head -1 "$SKILL_DIR/$part"
    [ "$output" != "---" ]
  done
}

@test "the orchestrator asks for vault changes in one line, with no diff, once for each card" {
  # The user reads the old and new text in the report, in the worker.
  run grep -n 'the note path, the old text and the new text' $(parts)
  [ "$status" -eq 1 ]
  grep -q 'I ask: apply the vault changes of <card title>?' "$SKILL_DIR/SKILL.md"
  grep -q 'do not ask again' "$SKILL_DIR/SKILL.md"
}
