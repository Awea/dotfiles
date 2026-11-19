#!/usr/bin/env bats
# config/rex/bin/folders.sh main-folder and folders: the folder of a new tab and the
# folders of a new session.
# Run: ASDF_BATS_VERSION=1.8.2 bats config/rex/test/

bats_require_minimum_version 1.5.0

setup() {
  # On macOS, TMPDIR is under /var, a link to /private/var: use the real path.
  BATS_TEST_TMPDIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset _Z_DATA
  AT="$BATS_TEST_DIRNAME/../bin/folders.sh"
}

@test "the Rex scripts use folders.sh, not herdr-app" {
  ! grep -q herdr-app "$BATS_TEST_DIRNAME/../bin/new-agent-tab.sh" "$BATS_TEST_DIRNAME/../bin/new-space.sh"
  grep -qF 'folders.sh' "$BATS_TEST_DIRNAME/../bin/new-agent-tab.sh"
  grep -qF 'folders.sh' "$BATS_TEST_DIRNAME/../bin/new-space.sh"
}
repo_with_worktree() {
  git init -q "$BATS_TEST_TMPDIR/main"
  git -C "$BATS_TEST_TMPDIR/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$BATS_TEST_TMPDIR/main" worktree add -q "$BATS_TEST_TMPDIR/wt"
}

@test "main-folder prints the folder outside git" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run bash "$AT" main-folder "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/plain" ]
}

@test "main-folder prints the main checkout of a linked worktree" {
  repo_with_worktree
  run bash "$AT" main-folder "$BATS_TEST_TMPDIR/wt"
  [ "$output" = "$BATS_TEST_TMPDIR/main" ]
}

@test "main-folder prints the folder of a main checkout" {
  repo_with_worktree
  run bash "$AT" main-folder "$BATS_TEST_TMPDIR/main"
  [ "$output" = "$BATS_TEST_TMPDIR/main" ]
}

@test "main-folder prints the folder when the main checkout is gone" {
  repo_with_worktree
  mv "$BATS_TEST_TMPDIR/main" "$BATS_TEST_TMPDIR/moved"
  run bash "$AT" main-folder "$BATS_TEST_TMPDIR/wt"
  [ "$output" = "$BATS_TEST_TMPDIR/wt" ]
}

@test "folders lists ~/.workspace first, then the z folders by frecency" {
  mkdir -p "$HOME/.workspace" "$HOME/a" "$HOME/b"
  now=$(date +%s)
  printf '%s|1|%s\n%s|50|%s\n%s|9|%s\n%s|5|%s\n' "$HOME/a" "$now" "$HOME/b" "$now" \
    "$HOME/gone" "$now" "$HOME/.workspace" "$now" >"$HOME/.z"
  run bash "$AT" folders
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = "$(jq -cn --arg h "$HOME" '[$h + "/.workspace", $h + "/b", $h + "/a"]')" ]
}

@test "folders works with no z file and no ~/.workspace" {
  run bash "$AT" folders
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = "$(jq -cn --arg h "$HOME" '[$h]')" ]
}
