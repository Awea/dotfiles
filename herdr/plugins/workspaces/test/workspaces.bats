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
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export HERDR_PLUGIN_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export AGENT_TABS_TITLE_TIMEOUT=0
  mkdir -p "$HERDR_PLUGIN_STATE_DIR" "$HERDR_PLUGIN_CONFIG_DIR"
  : >"$FAKE_LOG"
}

# Run the bash code $1 in a terminal. Type each next argument (a printf format) after
# a pause, so that the code is ready to read it. Set status to the exit code of the
# code, and output to the terminal output.
run_in_tty() {
  export TTY_CODE="$1"
  shift
  run script -qec 'bash -c "$TTY_CODE"' /dev/null < <(
    for keys in "$@"; do
      sleep 0.3
      printf "$keys"
    done
    sleep 0.5
  )
}

# Wait up to 5 seconds for the line $1 in the herdr log. The worker runs in the background.
wait_for_call() {
  local i
  for i in $(seq 50); do
    grep -qxF "$1" "$FAKE_LOG" && return 0
    sleep 0.1
  done
  return 1
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

@test "pick shows the keys for a shell and for claude" {
  run bash "$PLUGIN_DIR/new-workspace.sh" pick
  [ "$status" -eq 0 ]
  grep -qx -- '--expect=ctrl-a' "$FAKE_FZF_INPUT.args"
  grep -qx 'Enter for a shell. ctrl+a for claude. Esc to cancel.' "$FAKE_FZF_INPUT.args"
}

@test "pick with ctrl+a asks for the prompt, then starts claude in a new workspace" {
  export FAKE_KEY=ctrl-a FAKE_PICK=3
  run_in_tty "bash '$PLUGIN_DIR/new-workspace.sh' pick" 'fix the login test\r' 'h' 'y'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enter to confirm. Esc or ctrl+c to cancel."* ]]
  wait_for_call 'agent | prompt | w2:p1 | fix the login test'
  grep -qx "workspace | create | --cwd | $HOME/notes | --focus" "$FAKE_LOG"
  grep -qx 'agent | start | claude | --kind | claude | --pane | w2:p1 | --timeout | 60000 | -- | --effort | high' "$FAKE_LOG"
}

@test "pick with ctrl+a starts no worker after Esc" {
  export FAKE_KEY=ctrl-a
  run_in_tty "bash '$PLUGIN_DIR/new-workspace.sh' pick" 'hello' '\x1b'
  [ "$status" -eq 0 ]
  sleep 0.5
  ! grep -q '^workspace' "$FAKE_LOG"
}

@test "worker starts claude in a background workspace and sends the prompt" {
  run bash "$PLUGIN_DIR/new-workspace.sh" worker "$HOME/notes" 'fix "auth" & $HOME'
  [ "$status" -eq 0 ]
  grep -qx "workspace | create | --cwd | $HOME/notes | --no-focus" "$FAKE_LOG"
  grep -qx 'agent | start | claude | --kind | claude | --pane | w2:p1 | --timeout | 60000' "$FAKE_LOG"
  grep -qx 'agent | rename | w2:p1 | --clear' "$FAKE_LOG"
  grep -qx 'agent | prompt | w2:p1 | fix "auth" & $HOME' "$FAKE_LOG"
  grep -qx 'agent | rename | w2:p1 | fix-auth-home' "$FAKE_LOG"
}

@test "worker without prompt starts a clean claude with the effort" {
  run bash "$PLUGIN_DIR/new-workspace.sh" worker "$HOME/notes" '' low --focus
  [ "$status" -eq 0 ]
  grep -qx "workspace | create | --cwd | $HOME/notes | --focus" "$FAKE_LOG"
  grep -qx 'agent | start | claude | --kind | claude | --pane | w2:p1 | --timeout | 60000 | -- | --effort | low' "$FAKE_LOG"
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "worker stops and clears the agent name when claude does not start" {
  export FAKE_START_FAIL=1
  run bash "$PLUGIN_DIR/new-workspace.sh" worker "$HOME/notes" 'hello'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Claude did not start in the new workspace."* ]]
  grep -qx 'agent | rename | w2:p1 | --clear' "$FAKE_LOG"
  [ "$(grep -c '^agent | prompt' "$FAKE_LOG")" -eq 0 ]
}

@test "worker stops when the prompt fails" {
  export FAKE_PROMPT_FAIL=1
  run bash "$PLUGIN_DIR/new-workspace.sh" worker "$HOME/notes" 'hello'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Claude in w2:p1 did not get the prompt."* ]]
}
