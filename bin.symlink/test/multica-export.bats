#!/usr/bin/env bats
# Tests of multica-perso export, with the fixture vault and the fake multica CLI.
# shellcheck disable=SC2030,SC2031,SC2016 # Each test sets its own env: bats runs each test in a subshell.

load multica-helper

setup() {
  multica_setup
  "$MP" import >/dev/null
  MIRROR="$V/_multica/perso.md"
  CHANGES="$V/_multica/perso.changes.md"
}

# set_issue KEY JQ: change one issue of the fake state.
set_issue() {
  jq --arg k "$1" "map(if .identifier == \$k then $2 else . end)" "$FAKE_MULTICA_DIR/issues.json" >"$BATS_TEST_TMPDIR/i"
  mv "$BATS_TEST_TMPDIR/i" "$FAKE_MULTICA_DIR/issues.json"
}

# items KIND: the item lines of a kind.
items() { grep -E "^- \[[ x]\] mc-[0-9a-f]{8} $1 " "$CHANGES" || true; }

# move_card TITLE COLUMN CONTEXT: move the card of TITLE to COLUMN, with a new context line.
move_card() {
  awk -v t="**$1**" -v col="## $2" -v ctx="$3" '
    index($0, t) && /^- \[ \] / { card = $0; skip = 1; next }
    skip && /^\t/ { next }
    { skip = 0; lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        print lines[i]
        if (lines[i] == col) { print ""; print card; print "\t" ctx }
      }
    }' "$V/Boards/perso.md" >"$BATS_TEST_TMPDIR/b"
  mv "$BATS_TEST_TMPDIR/b" "$V/Boards/perso.md"
}

@test "the mirror has the 5 columns and one card per open issue" {
  run "$MP" export
  [ "$status" -eq 0 ]
  grep -qxF 'mirror: 5 cards' <<<"$output"
  head -3 "$MIRROR" | grep -qx 'kanban-plugin: board'
  for c in '📥 Backlog' '📋 This Week' '🔨 In Progress' '⏳ Waiting On' '✅ Done'; do
    grep -qxF "## $c" "$MIRROR" || { echo "no column $c"; return 1; }
  done
  [ "$(grep -c '^- \[' "$MIRROR")" -eq 5 ]
  grep -A1 -xF -- '- [ ] 🔴 **[beta] Fix the thing**' "$MIRROR" | tail -1 | grep -qxF "$(printf '\tContext of b. [[Projects/beta]] · PER-3')"
}

@test "an agent issue gives one with-agent item, a second export adds none" {
  set_issue PER-1 '.assignee_type = "agent"'
  run "$MP" export
  [ "$status" -eq 0 ]
  grep -qxF 'changes: 1 new, 0 closed' <<<"$output"
  [ "$(items with-agent | grep -cE '^- \[ \] mc-[0-9a-f]{8} with-agent PER-1: \[alpha\] Daily check → move to ⏳ Waiting On, context: in Multica PER-1$')" -eq 1 ]
  run "$MP" export
  grep -qxF 'changes: 0 new, 0 closed' <<<"$output"
  [ "$(items with-agent | grep -c .)" -eq 1 ]
}

@test "the item closes when the card is in Waiting On with the key" {
  set_issue PER-1 '.assignee_type = "agent"'
  "$MP" export
  move_card '[alpha] Daily check' '⏳ Waiting On' 'in Multica PER-1 [[Projects/alpha]]'
  run "$MP" export
  grep -qxF 'changes: 0 new, 1 closed' <<<"$output"
  items with-agent | grep -q '^- \[x\] '
}

@test "a RESULT comment gives a result item, with Done for a done issue" {
  set_issue PER-1 '.status = "done" | .metadata.vault_owner = "multica"'
  printf '%s\n' '{"id-1": [{"content": "First note.", "created_at": "2026-11-20T01:00:00Z"},
    {"content": "RESULT: DONE — fixed the check\nmore text", "created_at": "2026-11-20T02:00:00Z"}]}' \
    >"$FAKE_MULTICA_DIR/comments.json"
  "$MP" export
  [ "$(items result | grep -cxF -- "$(items result | grep -o '^- \[ \] mc-[0-9a-f]*') result PER-1: [alpha] Daily check → context: in Multica PER-1: RESULT: DONE — fixed the check, move to ✅ Done")" -eq 1 ]
}

@test "an issue made in Multica gives a new-card item" {
  alpha=$(jq -r '.[] | select(.title == "alpha") | .id' "$FAKE_MULTICA_DIR/projects.json")
  fake_issue "{\"title\": \"From Multica\", \"status\": \"todo\", \"priority\": \"high\", \"project_id\": \"$alpha\"}"
  "$MP" export
  items new-card | grep -qE '^- \[ \] mc-[0-9a-f]{8} new-card PER-6: From Multica → new card in 📋 This Week, priority 🟠, project alpha, context: in Multica PER-6$'
}

@test "a vault-owned status change gives a status item, a vault move gives none" {
  set_issue PER-3 '.status = "in_progress"'
  "$MP" export
  items status | grep -qE '^- \[ \] mc-[0-9a-f]{8} status PER-3: \[beta\] Fix the thing → move to 🔨 In Progress$'
  move_card '[alpha] Quote' '📋 This Week' 'Special title. [[Projects/alpha]]'
  "$MP" export
  [ "$(items status | grep -c .)" -eq 1 ]
}

@test "the special title is exact in the mirror and the item line" {
  set_issue PER-2 '.assignee_type = "agent"'
  "$MP" export
  grep -qxF -- '- [ ] 🟡 **[alpha] Quote "x" `y` | z: → w**' "$MIRROR"
  items with-agent | grep -qF 'with-agent PER-2: [alpha] Quote "x" `y` | z: → w → move to'
}

@test "a hand-edited line stays as it is" {
  set_issue PER-1 '.assignee_type = "agent"'
  "$MP" export
  printf 'notes by hand\n- [ ] mc-zz broken item\n' >>"$CHANGES"
  "$MP" export
  "$MP" export
  grep -qxF 'notes by hand' "$CHANGES"
  grep -qxF -- '- [ ] mc-zz broken item' "$CHANGES"
}

@test "the export writes nothing in Boards or _inbox" {
  mkdir -p "$V/_inbox"
  touch "$BATS_TEST_TMPDIR/stamp"
  sleep 1
  set_issue PER-1 '.assignee_type = "agent"'
  "$MP" export
  [ -z "$(find "$V/Boards" "$V/_inbox" -newer "$BATS_TEST_TMPDIR/stamp")" ]
  [ -f "$MIRROR" ] && [ -f "$CHANGES" ]
  [ -z "$(find "$V/_multica" -name '*.tmp*')" ]
}

@test "the mirror keeps the recurring mark and the date" {
  "$MP" export
  grep -qxF -- '- [ ] 🟢 🔁 **[alpha] Daily check** @{2000-01-01}' "$MIRROR"
}

@test "an issue with null fields does not break the mirror" {
  fake_issue '{"title": "Odd", "priority": null, "status": null}'
  run "$MP" export
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- \[' "$MIRROR")" -eq 5 ]
}

@test "a failed mirror keeps the old mirror" {
  "$MP" export
  cp "$MIRROR" "$BATS_TEST_TMPDIR/before"
  fake_issue '{"title": 5, "status": "todo"}'
  run "$MP" export
  [ "$status" -eq 1 ]
  cmp "$MIRROR" "$BATS_TEST_TMPDIR/before"
}
