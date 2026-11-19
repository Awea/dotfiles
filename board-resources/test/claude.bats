#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helper

setup() {
  br_setup
  export PATH="$WRAP:$FAKES:$PATH"
}

# with_timeout ARGS...: run ARGS with a 5 s limit (gtimeout on macOS).
with_timeout() {
  if command -v timeout >/dev/null; then timeout 5 "$@"; else gtimeout 5 "$@"; fi
}

@test "in a board folder it adds the board MCP and settings before the caller args" {
  cd "$HOME/ws/alpha/db1"
  run claude -n x
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_LOG")" = "--mcp-config=$BOARD_RESOURCES_HOME/alpha/mcp.json
--settings
$BOARD_RESOURCES_HOME/alpha/settings.json
-n
x" ]
}

@test "outside a board it adds nothing" {
  cd "$HOME"
  run claude -n x
  [ "$(cat "$FAKE_LOG")" = $'-n\nx' ]
}

@test "a board with no mcp.json gets only its settings" {
  cd "$HOME/ws/beta"
  run claude
  ! grep -q -- "--mcp-config" "$FAKE_LOG"
  grep -qx "$BOARD_RESOURCES_HOME/beta/settings.json" "$FAKE_LOG"
}

@test "a prompt argument gets the board flags" {
  cd "$HOME/ws/alpha"
  run claude "hello"
  grep -qx -- "--mcp-config=$BOARD_RESOURCES_HOME/alpha/mcp.json" "$FAKE_LOG"
  [ "$(tail -n 1 "$FAKE_LOG")" = hello ]
}

@test "a subcommand passes through unchanged" {
  cd "$HOME/ws/alpha"
  run claude mcp list
  [ "$(cat "$FAKE_LOG")" = $'mcp\nlist' ]
}

@test "--version passes through unchanged" {
  cd "$HOME/ws/alpha"
  run claude --version
  [ "$(cat "$FAKE_LOG")" = --version ]
}

@test "BOARD_RESOURCES_OFF=1 passes through unchanged" {
  cd "$HOME/ws/alpha"
  BOARD_RESOURCES_OFF=1 run claude -n x
  [ "$(cat "$FAKE_LOG")" = $'-n\nx' ]
}

@test "a caller --settings is kept and not doubled" {
  cd "$HOME/ws/alpha"
  run claude --settings '{}'
  [ "$(grep -c -- '--settings' "$FAKE_LOG")" -eq 1 ]
  grep -qx '{}' "$FAKE_LOG"
  grep -qx -- "--mcp-config=$BOARD_RESOURCES_HOME/alpha/mcp.json" "$FAKE_LOG"
}

@test "the wrapper folder twice on PATH does not loop" {
  cd "$HOME"
  PATH="$WRAP:$WRAP:$FAKES:$PATH" run with_timeout claude --version
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_LOG")" = --version ]
}

@test "a symlink to the wrapper folder on PATH does not loop" {
  ln -s "$WRAP" "$HOME/wl"
  cd "$HOME"
  PATH="$HOME/wl:$WRAP:$FAKES:$PATH" run with_timeout "$HOME/wl/claude" --version
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_LOG")" = --version ]
}

@test "no real claude on PATH: exit 127 with a message" {
  cd "$HOME"
  PATH="$WRAP:/usr/bin:/bin" run -127 claude --version
  [ "$status" -eq 127 ]
  [[ "$output" == *"no claude"* ]]
}

@test "a board with only mcp.json keeps a prompt as the prompt" {
  rm "$BOARD_RESOURCES_HOME/alpha/settings.json"
  cd "$HOME/ws/alpha"
  run claude "fix it" -p
  [ "$(cat "$FAKE_LOG")" = "--mcp-config=$BOARD_RESOURCES_HOME/alpha/mcp.json
fix it
-p" ]
}
