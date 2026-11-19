#!/usr/bin/env bats
# Tests that a job shell finds the asdf shims (mix, bats...).
# The Rex server takes the PATH of the desktop session, which reads
# ~/.profile. A `zsh -c` job also reads ~/.zshenv.
# Run: ASDF_BATS_VERSION=1.8.2 bats system/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ZSHENV="$REPO/zsh/zshenv.symlink"
PROFILE="$REPO/system/profile.symlink"

# The PATH of the desktop session before ~/.profile, as the Rex server gets it.
BARE_PATH=/usr/local/bin:/usr/bin:/bin

setup() {
  T="$BATS_TEST_TMPDIR/home"
  mkdir -p "$T/.asdf/shims" "$T/zdotdir"
  printf '#!/bin/sh\necho fake-mix\n' >"$T/.asdf/shims/mix"
  chmod +x "$T/.asdf/shims/mix"
  ln -s "$ZSHENV" "$T/zdotdir/.zshenv"
}

@test "a zsh -c job with a bare PATH finds mix in the asdf shims" {
  run env -i HOME="$T" PATH="$BARE_PATH" ZDOTDIR="$T/zdotdir" zsh -c 'command -v mix'
  [ "$status" -eq 0 ]
  [ "$output" = "$T/.asdf/shims/mix" ]
}

@test "a zsh started from a shell with the shims does not add them twice" {
  run env -i HOME="$T" PATH="$T/.asdf/shims:$BARE_PATH" ZDOTDIR="$T/zdotdir" zsh -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [ "$(tr : '\n' <<<"$output" | grep -cx "$T/.asdf/shims")" -eq 1 ]
}

@test "a bash -c job started from the session PATH of ~/.profile finds mix" {
  session_path=$(env -i HOME="$T" PATH="$BARE_PATH" sh -c '. "$1" && printf %s "$PATH"' sh "$PROFILE")
  run env -i HOME="$T" PATH="$session_path" bash -c 'command -v mix'
  [ "$status" -eq 0 ]
  [ "$output" = "$T/.asdf/shims/mix" ]
}

@test "~/.profile ends with status 0, so the session start logs no error" {
  run env -i HOME="$T" PATH="$BARE_PATH" sh -c '. "$1"' sh "$PROFILE"
  [ "$status" -eq 0 ]
}

@test "~/.profile puts the shims at the end, so the session keeps the system ruby" {
  run env -i HOME="$T" PATH="$BARE_PATH" sh -c '. "$1" && printf %s "$PATH"' sh "$PROFILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *":$T/.asdf/shims" ]]
}

@test "make links ~/.zshenv and ~/.profile" {
  run make -n -C "$REPO" HOME="$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/.zshenv" "$BATS_TEST_TMPDIR/.profile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -sfn $ZSHENV $BATS_TEST_TMPDIR/.zshenv"* ]]
  [[ "$output" == *"ln -sfn $PROFILE $BATS_TEST_TMPDIR/.profile"* ]]
}

@test "make links moves a plain ~/.profile away, also when it is newer" {
  H="$BATS_TEST_TMPDIR/h"
  mkdir -p "$H"
  echo old-profile >"$H/.profile"
  touch -t 203001010000 "$H/.profile"
  run make -C "$REPO" HOME="$H" "$H/.profile"
  [ "$status" -eq 0 ]
  [ "$(readlink "$H/.profile")" = "$PROFILE" ]
  [ "$(cat "$H/.profile.before-dotfiles")" = old-profile ]
}

@test "make links keeps an existing link to the repo file" {
  H="$BATS_TEST_TMPDIR/h"
  mkdir -p "$H"
  ln -s "$ZSHENV" "$H/.zshenv"
  run make -C "$REPO" HOME="$H" "$H/.zshenv"
  [ "$status" -eq 0 ]
  [ "$(readlink "$H/.zshenv")" = "$ZSHENV" ]
  [ ! -e "$H/.zshenv.before-dotfiles" ]
}
