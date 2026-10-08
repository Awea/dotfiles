#!/usr/bin/env bats
# Tests for the workspaces plugin script. A fake herdr records each call.

setup() {
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HERDR_BIN_PATH="$BATS_TEST_DIRNAME/fake-herdr"
  export HERDR_PLUGIN_ID="awea.workspaces"
  export FAKE_LOG="$BATS_TEST_TMPDIR/herdr.log"
  export FAKE_FZF_INPUT="$BATS_TEST_TMPDIR/fzf-input"
  export HOME="$BATS_TEST_TMPDIR/home"
  export _Z_DATA="$HOME/.z"
  # The fake fzf in a folder of its own, so that the tests do not use the real fzf.
  mkdir -p "$HOME/.workspace/old" "$HOME/.workspace/often" "$HOME/notes" "$BATS_TEST_TMPDIR/bin"
  ln -s "$BATS_TEST_DIRNAME/fake-fzf" "$BATS_TEST_TMPDIR/bin/fzf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  now=$(date +%s)
  # "often" has a high rank. "old" has the same rank as "notes", but a year ago.
  printf '%s|%s|%s\n' \
    "$HOME/.workspace/old" 10 $((now - 31536000)) \
    "$HOME/notes" 10 "$now" \
    "$HOME/.workspace/often" 80 "$now" \
    "$HOME/.workspace" 5 "$now" \
    "$HOME/gone" 99 "$now" >"$_Z_DATA"
  : >"$FAKE_LOG"
}

@test "list prints ~/.workspace first, then the z folders by frecency" {
  run bash "$PLUGIN_DIR/new-workspace.sh" list
  [ "$status" -eq 0 ]
  [ "$output" = $'~/.workspace\n~/.workspace/often\n~/notes\n~/.workspace/old' ]
}

@test "list prints HOME first when ~/.workspace does not exist" {
  rm -r "$HOME/.workspace"
  run bash "$PLUGIN_DIR/new-workspace.sh" list
  [ "$status" -eq 0 ]
  [ "$output" = $'~\n~/notes' ]
}

@test "list prints only the default folder without a z data file" {
  rm "$_Z_DATA"
  run bash "$PLUGIN_DIR/new-workspace.sh" list
  [ "$status" -eq 0 ]
  [ "$output" = '~/.workspace' ]
}

@test "open opens the popup" {
  run bash "$PLUGIN_DIR/new-workspace.sh" open
  [ "$status" -eq 0 ]
  grep -qx 'plugin | pane | open | --plugin | awea.workspaces | --entrypoint | pick' "$FAKE_LOG"
}

@test "pick creates a focused workspace in ~/.workspace on Enter" {
  run bash "$PLUGIN_DIR/new-workspace.sh" pick
  [ "$status" -eq 0 ]
  grep -qx "workspace | create | --cwd | $HOME/.workspace | --focus" "$FAKE_LOG"
}

@test "pick creates the workspace in the chosen folder" {
  export FAKE_PICK=3
  run bash "$PLUGIN_DIR/new-workspace.sh" pick
  [ "$status" -eq 0 ]
  grep -qx "workspace | create | --cwd | $HOME/notes | --focus" "$FAKE_LOG"
}

@test "pick creates no workspace on Esc" {
  export FAKE_CANCEL=1
  run bash "$PLUGIN_DIR/new-workspace.sh" pick
  [ "$status" -eq 0 ]
  ! grep -q '^workspace' "$FAKE_LOG"
}
