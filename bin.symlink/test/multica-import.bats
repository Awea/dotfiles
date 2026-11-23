#!/usr/bin/env bats
# Tests of multica-perso import, with the fixture vault and the fake multica CLI.
# shellcheck disable=SC2030,SC2031,SC2016 # Each test sets its own env: bats runs each test in a subshell.

load multica-helper

setup() { multica_setup; }

# vault_card_count VALUE: the count of issues with this vault_card metadata.
vault_card_count() {
  jq --arg v "$1" '[.[] | select(.metadata.vault_card == $v)] | length' "$FAKE_MULTICA_DIR/issues.json"
}

@test "a first import makes one issue per card with status, priority, project and metadata" {
  run "$MP" import
  [ "$status" -eq 0 ]
  [ "$(grep -c '^made PER-' <<<"$output")" -eq 5 ]
  [ "$(jq length "$FAKE_MULTICA_DIR/issues.json")" -eq 5 ]
  i=$(jq -c '.[] | select(.title == "[beta] Fix the thing")' "$FAKE_MULTICA_DIR/issues.json")
  [ "$(jq -r .status <<<"$i")" = todo ]
  [ "$(jq -r .priority <<<"$i")" = urgent ]
  [ "$(jq -r .metadata.vault_card <<<"$i")" = "beta/[beta] Fix the thing" ]
  [ "$(jq -r .metadata.vault_owner <<<"$i")" = vault ]
  [ "$(jq -r .metadata.vault_status <<<"$i")" = todo ]
  beta=$(jq -r '.[] | select(.title == "beta") | .id' "$FAKE_MULTICA_DIR/projects.json")
  [ "$(jq -r .project_id <<<"$i")" = "$beta" ]
  [ "$(jq -r .description <<<"$i")" = "$(printf 'Context of b. [[Projects/beta]]\n\nVault card: 📋 This Week')" ]
  [ "$(jq -r '.[] | select(.title == "[alpha] Ongoing") | .status' "$FAKE_MULTICA_DIR/issues.json")" = in_progress ]
  [ "$(jq -r '.[] | select(.title == "[beta] Same title") | .status' "$FAKE_MULTICA_DIR/issues.json")" = blocked ]
}

@test "a second import changes nothing" {
  "$MP" import
  : >"$FAKE_MULTICA_DIR/calls.log"
  run "$MP" import
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kept PER-' <<<"$output")" -eq 5 ]
  [ "$(fake_calls '^(issue (create|update|status|comment add|metadata set)|project (create|resource add))')" -eq 0 ]
}

@test "a card with a key updates that issue" {
  fake_issue '{}'
  fake_issue '{}'
  fake_issue '{"title": "old title", "status": "backlog"}'
  run "$MP" import
  [ "$status" -eq 0 ]
  grep -qxF 'updated PER-3 [alpha] Ongoing' <<<"$output"
  [ "$(issue PER-3 | jq -r .title)" = "[alpha] Ongoing" ]
  [ "$(issue PER-3 | jq -r .status)" = in_progress ]
  [ "$(issue PER-3 | jq -r .metadata.vault_card)" = "alpha/[alpha] Ongoing" ]
  # PER-1 and PER-2 have no vault_card: import leaves them as they are.
  [ "$(issue PER-1 | jq -r .title)" = t ]
}

@test "an agent issue is never changed" {
  fake_issue '{"title": "other", "assignee_type": "agent", "status": "in_review",
    "metadata": {"vault_card": "alpha/[alpha] Daily check", "vault_owner": "vault", "vault_status": "backlog"}}'
  run "$MP" import
  [ "$status" -eq 0 ]
  grep -qxF 'skipped PER-1 [alpha] Daily check (owned by Multica)' <<<"$output"
  [ "$(issue PER-1 | jq -r .metadata.vault_owner)" = multica ]
  [ "$(issue PER-1 | jq -r .title)" = other ]
  [ "$(fake_calls '^issue update (id-1|PER-1) ')" -eq 0 ]
}

@test "an issue with a run is never changed" {
  fake_issue '{"title": "other", "metadata": {"vault_card": "alpha/[alpha] Daily check", "vault_owner": "vault", "vault_status": "backlog"}}'
  echo '{"id-1": [{"id": "run-1", "status": "completed"}]}' >"$FAKE_MULTICA_DIR/runs.json"
  run "$MP" import
  grep -qxF 'skipped PER-1 [alpha] Daily check (owned by Multica)' <<<"$output"
  [ "$(issue PER-1 | jq -r .title)" = other ]
}

@test "a status moved in Multica is skipped and stays vault-owned" {
  fake_issue '{"title": "[beta] Fix the thing", "status": "in_progress", "priority": "urgent",
    "metadata": {"vault_card": "beta/[beta] Fix the thing", "vault_owner": "vault", "vault_status": "todo"}}'
  run "$MP" import
  [ "$status" -eq 0 ]
  grep -qxF 'skipped PER-1 [beta] Fix the thing (moved in Multica)' <<<"$output"
  [ "$(issue PER-1 | jq -r .status)" = in_progress ]
  [ "$(issue PER-1 | jq -r .metadata.vault_owner)" = vault ]
}

@test "a card gone from the vault cancels its vault-owned issue only" {
  fake_issue '{"title": "[alpha] Removed", "status": "todo",
    "metadata": {"vault_card": "alpha/[alpha] Removed", "vault_owner": "vault", "vault_status": "todo"}}'
  fake_issue '{"title": "[alpha] Agent work", "status": "in_progress",
    "metadata": {"vault_card": "alpha/[alpha] Agent work", "vault_owner": "multica"}}'
  fake_issue '{"title": "[alpha] Finished", "status": "done",
    "metadata": {"vault_card": "alpha/[alpha] Finished", "vault_owner": "vault", "vault_status": "todo"}}'
  run "$MP" import
  [ "$status" -eq 0 ]
  grep -qxF 'cancelled PER-1 [alpha] Removed' <<<"$output"
  [ "$(issue PER-1 | jq -r .status)" = cancelled ]
  [ "$(jq -r '.["id-1"][0].content' "$FAKE_MULTICA_DIR/comments.json")" = "Gone from the vault." ]
  [ "$(issue PER-2 | jq -r .status)" = in_progress ]
  [ "$(issue PER-3 | jq -r .status)" = "done" ]
}

@test "the special title is kept exact" {
  "$MP" import
  [ "$(vault_card_count 'alpha/[alpha] Quote "x" `y` | z: → w')" -eq 1 ]
  [ "$(jq '[.[] | select(.title == "[alpha] Quote \"x\" `y` | z: → w")] | length' "$FAKE_MULTICA_DIR/issues.json")" -eq 1 ]
}

@test "two cards with one key make one issue" {
  run "$MP" import
  grep -qxF 'skipped [beta] Same title (same key as line 24)' <<<"$output"
  [ "$(vault_card_count 'beta/[beta] Same title')" -eq 1 ]
}

@test "a CLI failure stops with exit 1, a rerun has no duplicate" {
  # The failure points: the first calls, and the call just after each issue create (its
  # metadata), where a lost issue would come back twice.
  "$MP" import >/dev/null
  points="1 2 3 $(grep -n '^issue create' "$FAKE_MULTICA_DIR/calls.log" | cut -d: -f1 | tr '\n' ' ')"
  for n in $points; do
    rm -rf "$FAKE_MULTICA_DIR"
    mkdir -p "$FAKE_MULTICA_DIR"
    echo "$n" >"$FAKE_MULTICA_DIR/fail_after"
    run "$MP" import
    rm "$FAKE_MULTICA_DIR/fail_after"
    if [ "$status" -ne 0 ]; then
      [ "$status" -eq 1 ] || { echo "n=$n status=$status"; return 1; }
      [[ "$output" == *"multica-perso: multica "*" failed"* ]] || { echo "n=$n: $output"; return 1; }
    fi
    run "$MP" import
    [ "$status" -eq 0 ] || { echo "n=$n rerun: $output"; return 1; }
    [ "$(jq length "$FAKE_MULTICA_DIR/issues.json")" -eq 5 ] || { echo "n=$n: $(jq -c 'map(.title)' "$FAKE_MULTICA_DIR/issues.json")"; return 1; }
    [ "$(jq length "$FAKE_MULTICA_DIR/projects.json")" -eq 2 ] || { echo "n=$n projects"; return 1; }
    [ "$(jq '[.[] | select(.metadata.vault_card == null)] | length' "$FAKE_MULTICA_DIR/issues.json")" -eq 0 ]
  done
}

@test "a GitHub repo is added to its project once" {
  "$MP" import
  "$MP" import
  [ "$(jq -c '.[] | select(.title == "alpha") | .resources' "$FAKE_MULTICA_DIR/projects.json")" = '[{"resource_type":"github_repo","resource_ref":{"url":"https://github.com/o/alpha"}}]' ]
  [ "$(jq -c '.[] | select(.title == "beta") | .resources' "$FAKE_MULTICA_DIR/projects.json")" = '[]' ]
}

# move_card TITLE COLUMN: move the card of TITLE, with its context, to COLUMN.
move_card() {
  awk -v t="**$1**" -v col="## $2" '
    index($0, t) && /^- \[ \] / { card = $0; skip = 1; next }
    skip && /^\t/ { ctx = ctx $0 "\n"; next }
    { skip = 0; lines[++n] = $0 }
    END { for (i = 1; i <= n; i++) { print lines[i]; if (lines[i] == col) { print ""; print card; printf "%s", ctx } } }' \
    "$V/Boards/perso.md" >"$BATS_TEST_TMPDIR/b"
  mv "$BATS_TEST_TMPDIR/b" "$V/Boards/perso.md"
}

@test "a Multica move applied to the card gives the issue back to the vault" {
  "$MP" import
  key=$(jq -r '.[] | select(.title == "[beta] Fix the thing") | .identifier' "$FAKE_MULTICA_DIR/issues.json")
  jq --arg k "$key" 'map(if .identifier == $k then .status = "in_progress" else . end)' "$FAKE_MULTICA_DIR/issues.json" >"$BATS_TEST_TMPDIR/i"
  mv "$BATS_TEST_TMPDIR/i" "$FAKE_MULTICA_DIR/issues.json"
  move_card '[beta] Fix the thing' '🔨 In Progress'
  run "$MP" import
  grep -qxF "updated $key [beta] Fix the thing" <<<"$output"
  [ "$(issue "$key" | jq -r .metadata.vault_status)" = in_progress ]
  sed -i.bak 's/^- \[ \] 🔴 \*\*\[beta\] Fix the thing\*\*/- [ ] 🟢 **[beta] Fix the thing**/' "$V/Boards/perso.md"
  run "$MP" import
  [ "$(issue "$key" | jq -r .priority)" = low ]
}

@test "a failure after a status update is repaired by the rerun" {
  "$MP" import
  move_card '[beta] Fix the thing' '🔨 In Progress'
  : >"$FAKE_MULTICA_DIR/calls.log"
  "$MP" import >/dev/null
  n=$(grep -n '^issue update' "$FAKE_MULTICA_DIR/calls.log" | head -1 | cut -d: -f1)
  # Do the same again on a fresh copy, failing just after that update.
  key=$(jq -r '.[] | select(.title == "[beta] Fix the thing") | .identifier' "$FAKE_MULTICA_DIR/issues.json")
  jq --arg k "$key" 'map(if .identifier == $k then .status = "todo" | .metadata.vault_status = "todo" else . end)' \
    "$FAKE_MULTICA_DIR/issues.json" >"$BATS_TEST_TMPDIR/i"
  mv "$BATS_TEST_TMPDIR/i" "$FAKE_MULTICA_DIR/issues.json"
  : >"$FAKE_MULTICA_DIR/calls.log"
  echo "$n" >"$FAKE_MULTICA_DIR/fail_after"
  run "$MP" import
  [ "$status" -eq 1 ]
  rm "$FAKE_MULTICA_DIR/fail_after"
  run "$MP" import
  [[ "$output" != *"moved in Multica"* ]]
  [ "$(issue "$key" | jq -r .metadata.vault_status)" = in_progress ]
}

@test "a card that comes back reopens its cancelled issue" {
  "$MP" import
  cp "$V/Boards/perso.md" "$BATS_TEST_TMPDIR/board"
  sed -i.bak '/\*\*\[beta\] Fix the thing\*\*/,+1d' "$V/Boards/perso.md"
  run "$MP" import
  key=$(jq -r '.[] | select(.title == "[beta] Fix the thing") | .identifier' "$FAKE_MULTICA_DIR/issues.json")
  grep -qxF "cancelled $key [beta] Fix the thing" <<<"$output"
  cp "$BATS_TEST_TMPDIR/board" "$V/Boards/perso.md"
  run "$MP" import
  grep -qxF "updated $key [beta] Fix the thing" <<<"$output"
  [ "$(issue "$key" | jq -r .status)" = todo ]
}

@test "an adopted Multica issue keeps its description" {
  alpha_desc='Long notes typed in Multica.'
  fake_issue "{\"title\": \"From Multica\", \"description\": \"$alpha_desc\", \"status\": \"todo\"}"
  printf '%s\n' '- [ ] 🟢 **[alpha] From Multica**' '	in Multica PER-1 [[Projects/alpha]]' >"$BATS_TEST_TMPDIR/card"
  sed -i.bak "/^## 📋 This Week/r $BATS_TEST_TMPDIR/card" "$V/Boards/perso.md"
  "$MP" import
  "$MP" import
  [ "$(issue PER-1 | jq -r .description)" = "$alpha_desc" ]
  [ "$(issue PER-1 | jq -r .title)" = "[alpha] From Multica" ]
}

@test "the description keeps the date of the card" {
  "$MP" import
  d=$(jq -r '.[] | select(.title == "[alpha] Daily check") | .description' "$FAKE_MULTICA_DIR/issues.json")
  [ "$d" = "$(printf 'Last run ok. [[Projects/alpha]]\n\nVault card: 📥 Backlog\nRecurring\nDate: 2000-01-01')" ]
}
