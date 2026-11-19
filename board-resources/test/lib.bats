#!/usr/bin/env bats

load helper

setup() {
  br_setup
  # shellcheck source=../lib.sh
  source "$BR_DIR/lib.sh"
}

@test "a folder under a root maps to its board" {
  mkdir -p "$HOME/ws/alpha/db1/a"
  run board_of "$HOME/ws/alpha/db1/a"
  [ "$status" -eq 0 ]
  [ "$output" = alpha ]
}

@test "the root itself maps to its board" {
  run board_of "$HOME/ws/alpha"
  [ "$status" -eq 0 ]
  [ "$output" = alpha ]
}

@test "a sibling with the same prefix maps to no board" {
  mkdir -p "$HOME/ws/alpha-old"
  run board_of "$HOME/ws/alpha-old"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a glob root matches a beta worktree" {
  mkdir -p "$HOME/ws/beta-1326/src"
  run board_of "$HOME/ws/beta-1326/src"
  [ "$status" -eq 0 ]
  [ "$output" = beta ]
}

@test "a glob root with no match gives no board" {
  run board_of "$HOME"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a symlinked folder maps to the board of its real path" {
  ln -s "$HOME/ws/alpha" "$HOME/link"
  run board_of "$HOME/link/db1"
  [ "$status" -eq 0 ]
  [ "$output" = alpha ]
}

@test "a symlinked root maps its real folder" {
  mkdir -p "$HOME/real/x"
  ln -s "$HOME/real" "$HOME/ws/linked"
  mkdir -p "$BOARD_RESOURCES_HOME/lnk"
  printf '~/ws/linked\n' >"$BOARD_RESOURCES_HOME/lnk/roots"
  run board_of "$HOME/real/x"
  [ "$output" = lnk ]
}

@test "two matching roots: the longest wins" {
  mkdir -p "$BOARD_RESOURCES_HOME/inner"
  printf '~/ws/alpha/db1\n' >"$BOARD_RESOURCES_HOME/inner/roots"
  run board_of "$HOME/ws/alpha/db1"
  [ "$output" = inner ]
  run board_of "$HOME/ws/alpha"
  [ "$output" = alpha ]
}

@test "a missing config folder gives no board and no error" {
  rm -rf "$BOARD_RESOURCES_HOME"
  run board_of "$HOME"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a missing folder gives no board and no error" {
  run board_of "$HOME/nope"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "board_file prints only an existing file" {
  run board_file beta mcp.json
  [ "$status" -eq 1 ]
  run board_file alpha mcp.json
  [ "$status" -eq 0 ]
  [ "$output" = "$BOARD_RESOURCES_HOME/alpha/mcp.json" ]
}

@test "expand_path replaces a leading tilde only" {
  run expand_path '~/a/~b'
  [ "$output" = "$HOME/a/~b" ]
  run expand_path '/x/~'
  [ "$output" = '/x/~' ]
}

@test "board_of resolves each root line once, not each glob match" {
  for i in $(seq 1 50); do mkdir -p "$HOME/ws/beta-$i"; done
  counter="$BATS_TEST_TMPDIR/real-dir-calls"
  : >"$counter"
  eval "orig_$(declare -f real_dir)"
  real_dir() { echo x >>"$counter"; orig_real_dir "$@"; }
  run board_of "$HOME/ws/beta-7"
  [ "$output" = beta ]
  [ "$(wc -l <"$counter")" -le 5 ]
}

@test "a glob root matches only the folder part it names" {
  mkdir -p "$HOME/ws/beta-x/beta-y" "$HOME/ws/other/beta-z"
  run board_of "$HOME/ws/other/beta-z"
  [ "$status" -eq 1 ]
  run board_of "$HOME/ws/beta-x/beta-y"
  [ "$output" = beta ]
}

# home_of ENV...: the BOARD_RESOURCES_HOME that lib.sh picks with only ENV set.
home_of() {
  env -u BOARD_RESOURCES_HOME -u OBSIDIAN_VAULT_PATH "$@" \
    bash -c 'source "$1/lib.sh" && printf "%s\n" "$BOARD_RESOURCES_HOME"' _ "$BR_DIR"
}

@test "the config is in the vault of OBSIDIAN_VAULT_PATH" {
  run home_of HOME="$HOME" OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/vault/_board-resources" ]
}

@test "with no OBSIDIAN_VAULT_PATH the config is in the vault of the Claude settings" {
  mkdir -p "$HOME/.claude"
  printf '{"env":{"OBSIDIAN_VAULT_PATH":"%s"}}\n' "$BATS_TEST_TMPDIR/vault2" >"$HOME/.claude/settings.json"
  run home_of HOME="$HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/vault2/_board-resources" ]
}

@test "with no vault the config is in ~/.config/board-resources" {
  run home_of HOME="$HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/board-resources" ]
}

@test "BOARD_RESOURCES_HOME wins over the vault" {
  run home_of HOME="$HOME" OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault" BOARD_RESOURCES_HOME=/x
  [ "$status" -eq 0 ]
  [ "$output" = /x ]
}
