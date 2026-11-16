#!/usr/bin/env bats
# agent-tabs.sh main-folder and folders.

bats_require_minimum_version 1.5.0
load helper

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
