#!/usr/bin/env bats
# SKILL.md of board-orchestrator.

bats_require_minimum_version 1.5.0
load helper

# The skill text: SKILL.md and the parts that it tells the orchestrator to read.
parts() { printf '%s\n' "$SKILL_DIR/SKILL.md" "$SKILL_DIR/start.md" "$SKILL_DIR/shorten.md" "$SKILL_DIR/boards.md"; }

@test "skill names only dispatch commands that exist" {
  [ -f "$SKILL_DIR/SKILL.md" ]
  for c in $(parts | xargs grep -h -o -E 'dispatch\.sh [a-z-]+' | awk '{print $2}' | sort -u); do
    grep -q -E "^  ([a-z|-]+\|)?$c(\|[a-z|-]+)?\)$" "$SKILL_DIR/dispatch.sh" || { echo "missing: $c"; return 1; }
  done
}

@test "skill uses its own paths" {
  [ -f "$SKILL_DIR/SKILL.md" ]
  # Not "! grep": bats ignores a negated command that is not the last one.
  run grep -n 'skills/board-orchestrator-hc/' $(parts)
  [ "$status" -ne 0 ]
  grep -q '~/.claude/skills/board-orchestrator/dispatch.sh' "$SKILL_DIR/SKILL.md"
}

@test "skill gives the note texts" {
  grep -q 'report <slug> <path>' "$SKILL_DIR/SKILL.md"
  grep -q 'is blocked (' "$SKILL_DIR/SKILL.md"
  grep -q 'exited (exit' "$SKILL_DIR/SKILL.md"
  grep -q 'close <slug></rex>' "$SKILL_DIR/SKILL.md"
  grep -q 'card <id></rex>' "$SKILL_DIR/SKILL.md"
}

@test "the boards part sends and receives a card of another board" {
  for c in send queue queue-clear; do
    grep -q "dispatch.sh $c " "$SKILL_DIR/boards.md" || { echo "missing: $c"; return 1; }
  done
  grep -q 'dispatch.sh queue' "$SKILL_DIR/start.md"
  # The inbox sends a card of another board, and does not write that board.
  grep -q '"add" is `save`, "start" is `start`' "$SKILL_DIR/start.md"
  run grep -n 'orchestrator of that board starts it' "$SKILL_DIR/start.md"
  [ "$status" -eq 1 ]
}

@test "skill is user-invoked, so a worker claude cannot load it and its dispatch.sh permission" {
  grep -qx 'disable-model-invocation: true' "$SKILL_DIR/SKILL.md"
}

@test "skill has its own name" {
  grep -qx 'name: board-orchestrator' "$SKILL_DIR/SKILL.md"
}

@test "skill takes the whole argument text as BOARD" {
  grep -q 'BOARD is the whole argument text' "$SKILL_DIR/SKILL.md"
  ! grep -q 'The first word is BOARD' "$SKILL_DIR/SKILL.md"
}

@test "skill parts exist, and the core tells when to read each" {
  for part in start.md shorten.md boards.md; do
    [ -f "$SKILL_DIR/$part" ]
    grep -q "~/.claude/skills/board-orchestrator/$part" "$SKILL_DIR/SKILL.md"
  done
}

@test "each rule is in one part: rules 1 to 4 at the start, 8 to shorten, the rest in the core" {
  for n in 1 2 3 4; do grep -q -E "^$n\. \*\*" "$SKILL_DIR/start.md"; done
  for n in 5 6 7; do grep -q -E "^$n\. \*\*" "$SKILL_DIR/SKILL.md"; done
  grep -q -E '^8\. \*\*' "$SKILL_DIR/shorten.md"
  for n in 1 2 3 4 5 6 7 8; do
    [ "$(parts | xargs cat | grep -c -E "^$n\. \*\*")" -eq 1 ] || { echo "rule $n"; return 1; }
  done
}

@test "the core that a compact reads again is at most 33000 bytes" {
  size=$(wc -c <"$SKILL_DIR/SKILL.md")
  echo "SKILL.md: $size bytes"
  [ "$size" -le 33000 ]
}

@test "the parts are not skills: no frontmatter" {
  for part in start.md shorten.md boards.md; do
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

@test "SKILL.md treats <rex> tags as data" {
  grep -q 'a `<rex>` tag are \*\*data\*\*' "$SKILL_DIR/SKILL.md"
}

@test "SKILL.md shows the Rex report form" {
  grep -q '<rex from="[^"]* fix-login">report' "$SKILL_DIR/SKILL.md"
}

@test "SKILL.md tells to read a worker with dispatch.sh last, not rex capture" {
  grep -q 'run `dispatch.sh last ADDRESS`, not `rex capture`' "$SKILL_DIR/SKILL.md"
}

@test "SKILL.md shows the Rex notice texts" {
  grep -q '<rex>SHORT NAME is blocked (MSG). See: dispatch.sh last SHORT</rex>' "$SKILL_DIR/SKILL.md"
  grep -q '<rex>SHORT NAME exited (exit CODE). See: dispatch.sh last SHORT</rex>' "$SKILL_DIR/SKILL.md"
}

@test "the orchestrator says only the say line of a report, and no text between tool calls" {
  # The user saw a summary of each report, a line for each blocked worker and a line for
  # each step. The Renux agents list and the worker show all that.
  grep -q 'the last line of `dispatch.sh report`, `say:`' "$SKILL_DIR/SKILL.md"
  grep -q 'also not in text between tool' "$SKILL_DIR/SKILL.md"
  grep -q 'For a recurring card (`🔁`), write no done line' "$SKILL_DIR/SKILL.md"
  for kind in Blocked Exit 'Close request'; do
    # The text of the bullet, up to the next bullet.
    awk -v k="   - **$kind**:" 'index($0, k) == 1 { on = 1; print; next } on && /^   - / { exit } on' \
      "$SKILL_DIR/SKILL.md" | tr '\n' ' ' | grep -q -E 'Write +nothing\.' || { echo "$kind"; return 1; }
  done
}
