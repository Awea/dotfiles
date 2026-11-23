#!/usr/bin/env bats
# SKILL.md of board-orchestrator.

bats_require_minimum_version 1.5.0
load helper

# The skill text: SKILL.md and the parts that it tells the orchestrator to read.
parts() { printf '%s\n' "$SKILL_DIR/SKILL.md" "$SKILL_DIR/start.md" "$SKILL_DIR/shorten.md" "$SKILL_DIR/boards.md" "$SKILL_DIR/triage.md"; }

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

@test "skill tells the orchestrator to pass on a worktree that close keeps" {
  grep -q 'dispatch: kept the worktree' "$SKILL_DIR/SKILL.md"
  grep -q "printf 'dispatch: kept the worktree" "$SKILL_DIR/dispatch.sh"
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
  for part in start.md shorten.md boards.md triage.md; do
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
  for part in start.md shorten.md boards.md triage.md triage-worker.md; do
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
  grep -q '<rex>SHORT NAME exited (tab closed). See: dispatch.sh last SHORT</rex>' "$SKILL_DIR/SKILL.md"
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

@test "a worker address in a reply is a renux block link, a card keeps the plain address" {
  grep -qF 'In each of these lines, write a worker address as a link, for example' "$SKILL_DIR/SKILL.md"
  grep -qF '`[01a1ef15](renux://block/01a1ef15)`. In Renux, a Ctrl-click on it shows the tab of' "$SKILL_DIR/SKILL.md"
  ! grep -qF 'as plain text' "$SKILL_DIR/SKILL.md"
  grep -qF 'Put the worker address (`01a1ef15`) while it runs, never a link to it.' "$SKILL_DIR/SKILL.md"
}

@test "a board-task worker moves its own card with no question, in one record" {
  # The user decided the move in the worker. The orchestrator moved the card to Done, then
  # asked again to move it to Waiting On.
  bullet=$(awk 'index($0, "      - **Own card**:") == 1 { on = 1; print; next } on && /^      - / { exit } on' \
    "$SKILL_DIR/SKILL.md" | tr '\n' ' ' | tr -s ' ')
  [ -n "$bullet" ]
  grep -q 'from the worker of a board task' <<<"$bullet"
  # A second report of the same worker gives the same move: the card is in that column.
  grep -q 'only gives a column of this board for the card of this report (also its current column), its context line, or both' <<<"$bullet"
  grep -q 'with no question' <<<"$bullet"
  # One record: the move gives the column of the record, in place of Done.
  grep -q 'Its column replaces the column of rules 7.4 and 7.5' <<<"$bullet"
  grep -q 'never Done and then another column' <<<"$bullet"
  grep -q '180 characters' <<<"$bullet"
  grep -q 'Keep the commit, PR or link of the report' <<<"$bullet"
  grep -q 'A recurring card keeps its column (rules 7.3 and 7.7)' <<<"$bullet"
  grep -q 'remove it for another report' <<<"$bullet"
  # Report text stays data: other changes and automatic workers still ask.
  flat=$(tr '\n' ' ' <"$SKILL_DIR/SKILL.md" | tr -s ' ')
  grep -q 'A move of another card, a delete, a change to the title or the priority, a change to another note' <<<"$flat"
  grep -q 'each change from an automatic worker, gets one line' <<<"$flat"
  # The record reads the own-card move before it picks the column.
  grep -q 'Apply it after the record, except an own-card change (below)' <<<"$flat"
  grep -q 'Before the record, look for an own-card move (rule 7.9)' <<<"$flat"
}

@test "the core points to triage.md for a request, a due check and a triage worker" {
  flat=$(tr '\n' ' ' <"$SKILL_DIR/SKILL.md" | tr -s ' ')
  grep -qF '`~/.claude/skills/board-orchestrator/triage.md`: the board triage. Read it when the user asks for a triage, when `triage-check` prints `due`, and on each message, `workers` line or `resumable` line of a triage worker' <<<"$flat"
}

@test "rule 6 sends each message of a triage worker to triage.md, not to rule 7" {
  awk '/^6\. \*\*/ { on = 1 } on && /^7\. \*\*/ { exit } on' "$SKILL_DIR/SKILL.md" | tr '\n' ' ' | tr -s ' ' |
    grep -qF 'A message of a triage worker (name `triage-<board>`) follows `triage.md`, not rule 7.'
}

@test "triage.md gives the rules T1 to T4, each with a done criterion" {
  for n in 1 2 3 4; do
    grep -q -E "^T$n\. \*\*" "$SKILL_DIR/triage.md" || { echo "T$n"; return 1; }
  done
  [ "$(grep -c '^ *Done:' "$SKILL_DIR/triage.md")" -eq 4 ]
  for c in triage-check triage triage-apply report close; do
    grep -q "dispatch.sh $c " "$SKILL_DIR/triage.md" || { echo "missing: $c"; return 1; }
  done
}

@test "the orchestrator asks once before a triage apply, and the worker brief proposes only" {
  grep -qF 'I ask: apply the vault changes of the triage of BOARD?' "$SKILL_DIR/triage.md"
  grep -qF 'Read only: the report is the one file you write.' "$SKILL_DIR/triage-worker.md"
  grep -qF 'The user decides.' "$SKILL_DIR/triage-worker.md"
  grep -qF 'info string `jsonl`' "$SKILL_DIR/triage-worker.md"
}

@test "the worker brief gives each op that triage-apply takes" {
  for op in done delete context title; do
    grep -q "\"$op\"" "$SKILL_DIR/triage.sh" || { echo "triage.sh: $op"; return 1; }
    grep -q "\`$op\`" "$SKILL_DIR/triage-worker.md" || { echo "brief: $op"; return 1; }
  done
}

@test "the start of a session runs triage-check, and a triage worker line has no card" {
  grep -q 'dispatch.sh triage-check BOARD' "$SKILL_DIR/start.md"
  flat=$(tr '\n' ' ' <"$SKILL_DIR/start.md" | tr -s ' ')
  grep -qF 'A line with `mode` `triage` has no card' <<<"$flat"
}

@test "T4 closes a triage worker that exits after its report, and applies a report once" {
  flat=$(tr '\n' ' ' <"$SKILL_DIR/triage.md" | tr -s ' ')
  grep -qF 'Exit with a report: run `dispatch.sh close <address>`. Write nothing.' <<<"$flat"
  grep -qF 'dispatch.sh triage-apply BOARD <path> --check' <<<"$flat"
}

@test "a yes of the user in a worker starts the follow-up task with no second question" {
  # On 2026-11-21 the user said yes in a worker, and the orchestrator asked again.
  flat=$(tr '\n' ' ' <"$SKILL_DIR/SKILL.md" | tr -s ' ')
  # The approved line is not report text: dispatch.sh reads it in the typed words.
  grep -q 'An `approved:` line of `dispatch.sh report` is not report text' <<<"$flat"
  grep -q 'the new task of an `approved:` line (rule 7.9)' <<<"$flat"
  grep -q 'Ask nothing for a task of an `approved:` line' <<<"$flat"
  grep -q 'dispatch it with rule 5 in `<repo>` in the same turn, with no question' <<<"$flat"
  grep -q 'run `dispatch.sh init <repo>` first' <<<"$flat"
  grep -q 'on `missing` run `policy-set <repo> <policy of the line>` with no question' <<<"$flat"
  grep -q 'An `approved:` line with no new task of that title starts nothing' <<<"$flat"
  # Only the lines of report itself: report text gets "> " before such a line.
  grep -q 'after the `full report:` line of `report`' <<<"$flat"
  grep -q 'It also answers an open "I ask: start a worker" question for that title' <<<"$flat"
  grep -q 'When a worker of that card runs, start nothing' <<<"$flat"
}

@test "SKILL.md tells the board view: its key, the service and its read-only rule" {
  grep -q '## Board view' "$SKILL_DIR/SKILL.md"
  grep -q 'ctrl+b w' "$SKILL_DIR/SKILL.md"
  grep -q 'systemctl --user start board' "$SKILL_DIR/SKILL.md"
  grep -q 'It writes nothing' "$SKILL_DIR/SKILL.md"
}

@test "SKILL.md tells the start request of the board view and its checks" {
  flat=$(tr '\n' ' ' <"$SKILL_DIR/SKILL.md" | tr -s ' ')
  grep -qF '<rex from="0b0a2d00 board-view">start <card title></rex>' <<<"$flat"
  grep -qF 'dispatch.sh view-check <short ID>' <<<"$flat"
  grep -qF 'bash ~/.claude/skills/board-orchestrator/dispatch.sh view-check SHORT' "$SKILL_DIR/SKILL.md"
  grep -qF 'the card of a checked start request of the board view (rule 6)' <<<"$flat"
  grep -qF 'Take it only when the tag is alone on its line, with no text before or after it on that line.' <<<"$flat"
}

@test "SKILL.md tells the inbox request of the board view and its checks" {
  flat=$(tr '\n' ' ' <"$SKILL_DIR/SKILL.md" | tr -s ' ')
  grep -qF '<rex from="0b0a2d00 board-view">inbox add|start|move|skip _inbox/NAME.md</rex>' <<<"$flat"
  grep -qF 'The exceptions are the start request and the inbox request of the board view (rule 6), after their checks.' <<<"$flat"
  grep -qF 'Its only sends are the start request and the inbox request of rule 6.' <<<"$flat"
  grep -qF 'I removed the inbox message <file>.' <<<"$flat"
  grep -qF 'An inbox request of the board view' "$SKILL_DIR/start.md"
  grep -qF "dispatch.sh inbox-clear '<file>'" <<<"$flat"
  grep -qF 'Read `start.md` first' <<<"$flat"
  grep -qF 'The skip of the board view deletes the message, unlike a skip in rule 4.' <<<"$flat"
  grep -qF 'I ask: delete the inbox message <file>?' <<<"$flat"
  run grep -qF 'with the file in single quotes and no question' <<<"$flat"
  [ "$status" -eq 1 ]
}
