#!/usr/bin/env bats
# Tests of multica/lib.sh, with the fixture vault and the fake multica CLI.
# shellcheck disable=SC2030,SC2031,SC2016 # Each test sets its own env: bats runs each test in a subshell.

load multica-helper

setup() {
  multica_setup
  # shellcheck disable=SC1091 # The repo path is known at run time only.
  source "$BIN/../multica/lib.sh"
}

@test "mp_vault_cards gives the full fields of each open card" {
  run mp_vault_cards perso
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 6 ]
  line=$(jq -c 'select(.title == "[alpha] Ongoing")' <<<"$output")
  [ "$(jq -r .key <<<"$line")" = PER-3 ]
  [ "$(jq -r .column <<<"$line")" = "🔨 In Progress" ]
  [ "$(jq -r .project <<<"$line")" = alpha ]
  [ "$(jq -r .repo <<<"$line")" = "$HOME/code/alpha" ]
  [ "$(jq -r .context <<<"$line")" = "in Multica PER-3, started. [[Projects/alpha]]" ]
  [ "$(jq -r 'select(.line == 9) | .title' <<<"$output")" = '[alpha] Quote "x" `y` | z: → w' ]
  [ "$(jq -r 'select(.line == 7) | .recurring' <<<"$output")" = true ]
  [ "$(jq -r 'select(.line == 26) | .context' <<<"$output")" = "Second. [[Projects/beta]]" ]
  [ "$(jq -r 'select(.line == 26) | .repo' <<<"$output")" = null ]
  [ "$(jq -r 'select(.line == 24) | .key' <<<"$output")" = null ]
}

@test "mp_issues reads all pages" {
  jq -n '[range(1; 231) | {id: "id-\(.)", identifier: "PER-\(.)", title: "t\(.)", status: "todo",
    priority: "none", assignee_type: null, project_id: null, metadata: {}, description: "",
    updated_at: "2026-11-20T00:00:00Z"}]' >"$BATS_TEST_TMPDIR/issues.json"
  mkdir -p "$FAKE_MULTICA_DIR"
  mv "$BATS_TEST_TMPDIR/issues.json" "$FAKE_MULTICA_DIR/issues.json"
  run mp_issues
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 230 ]
  [ "$(fake_calls '^issue list')" -eq 3 ]
}

@test "mp_cli reports a failed call" {
  mkdir -p "$FAKE_MULTICA_DIR"
  echo 0 >"$FAKE_MULTICA_DIR/fail_after"
  run mp_cli issue list --output json
  [ "$status" -eq 1 ]
  [[ "$output" == *"multica-perso: multica issue list --output json failed"* ]]
}

@test "mp_projects accepts an array or an object" {
  mkdir -p "$FAKE_MULTICA_DIR"
  echo '[{"id":"p1","title":"alpha"}]' >"$FAKE_MULTICA_DIR/projects.json"
  run mp_projects
  [ "$output" = '{"id":"p1","title":"alpha"}' ]
  echo '{"projects":[{"id":"p2","title":"beta"}]}' >"$FAKE_MULTICA_DIR/projects.json"
  run mp_projects
  [ "$output" = '{"id":"p2","title":"beta"}' ]
}

@test "the maps follow the constraints" {
  [ "$(mp_status_of '📥 Backlog')" = backlog ]
  [ "$(mp_status_of '📋 This Week')" = todo ]
  [ "$(mp_status_of '🔨 In Progress')" = in_progress ]
  [ "$(mp_status_of '⏳ Waiting On')" = blocked ]
  [ "$(mp_column_of backlog)" = '📥 Backlog' ]
  [ "$(mp_column_of todo)" = '📋 This Week' ]
  [ "$(mp_column_of in_progress)" = '🔨 In Progress' ]
  [ "$(mp_column_of blocked)" = '⏳ Waiting On' ]
  [ "$(mp_column_of in_review)" = '⏳ Waiting On' ]
  [ "$(mp_column_of 'done')" = '✅ Done' ]
  [ "$(mp_column_of cancelled)" = '' ]
  [ "$(mp_priority_of 🔴)" = urgent ]
  [ "$(mp_priority_of 🟠)" = high ]
  [ "$(mp_priority_of 🟡)" = medium ]
  [ "$(mp_priority_of 🟢)" = low ]
  [ "$(mp_priority_of '')" = none ]
  [ "$(mp_emoji_of urgent)" = 🔴 ]
  [ "$(mp_emoji_of high)" = 🟠 ]
  [ "$(mp_emoji_of medium)" = 🟡 ]
  [ "$(mp_emoji_of low)" = 🟢 ]
  [ "$(mp_emoji_of none)" = '' ]
}

@test "mp_issues accepts a bare array" {
  fake_issue '{}'
  FAKE_MULTICA_LIST_SHAPE=array run mp_issues
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 1 ]
}

@test "mp_issues fails on an unknown shape" {
  FAKE_MULTICA_LIST_SHAPE=bad run mp_issues
  [ "$status" -eq 1 ]
  [[ "$output" == *"multica-perso: unknown issue list"* ]]
}

@test "mp_issues stops on an empty page" {
  FAKE_MULTICA_LIST_SHAPE=empty run timeout 10 bash -c "source '$BIN/../multica/lib.sh'; mp_issues"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mp_vault_cards gives the date of a card" {
  run mp_vault_cards perso
  [ "$(jq -r 'select(.line == 7) | .date' <<<"$output")" = 2000-01-01 ]
}
