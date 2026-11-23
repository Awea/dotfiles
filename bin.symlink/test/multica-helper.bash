# shellcheck shell=bash
# Common setup of the multica-perso tests: a copy of the fixture vault, a fake multica CLI
# and a HOME with the repo of the project alpha.

# shellcheck disable=SC2034 # The test files use these names.
multica_setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  MP="$BIN/multica-perso"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  export FAKE_MULTICA_DIR="$BATS_TEST_TMPDIR/multica"
  export MULTICA_BIN="$BIN/test/fake-multica"
  V="$OBSIDIAN_VAULT_PATH"
  mkdir -p "$HOME/code/alpha"
  cp -R "$BIN/test/fixtures/multica/vault" "$V"
  git -C "$HOME/code/alpha" init -q
  git -C "$HOME/code/alpha" remote add origin git@github.com:o/alpha.git
}

# fake_calls PATTERN: the count of fake CLI calls that match PATTERN (grep -E).
fake_calls() { grep -cE -- "$1" "$FAKE_MULTICA_DIR/calls.log" || true; }

# fake_issue JSON: add one issue to the fake state, with the default fields.
fake_issue() {
  mkdir -p "$FAKE_MULTICA_DIR"
  [ -f "$FAKE_MULTICA_DIR/issues.json" ] || echo '[]' >"$FAKE_MULTICA_DIR/issues.json"
  local n
  n=$(($(cat "$FAKE_MULTICA_DIR/n" 2>/dev/null || echo 0) + 1))
  echo "$n" >"$FAKE_MULTICA_DIR/n"
  jq --argjson n "$n" --argjson i "$1" '. + [{id: "id-\($n)", identifier: "PER-\($n)", number: $n,
    title: "t", description: "", status: "backlog", priority: "none", assignee_type: null,
    assignee_id: null, project_id: null, metadata: {}, created_at: "2026-11-20T00:00:00Z",
    updated_at: "2026-11-20T00:00:00Z"} + $i]' "$FAKE_MULTICA_DIR/issues.json" >"$FAKE_MULTICA_DIR/i.tmp"
  mv "$FAKE_MULTICA_DIR/i.tmp" "$FAKE_MULTICA_DIR/issues.json"
}

# issue KEY: the JSON of one issue of the fake state.
issue() { jq -c --arg k "$1" '.[] | select(.identifier == $k)' "$FAKE_MULTICA_DIR/issues.json"; }
