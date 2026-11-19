#!/usr/bin/env bats
# Tests for claude/hooks/plugin-skill-overrides.sh.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/hooks/test/

SCRIPT="$BATS_TEST_DIRNAME/../plugin-skill-overrides.sh"

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  PLUGIN="$CLAUDE_CONFIG_DIR/plugins/cache/mkt/demo/1.0.0"
  mkdir -p "$PLUGIN/commands" "$PLUGIN/skills/deep"
  printf -- '---\ndescription: Alpha command\n---\nSay alpha.\n' > "$PLUGIN/commands/alpha.md"
  printf -- '---\ndescription: Beta command\n---\nSay beta.\n' > "$PLUGIN/commands/beta.md"
  printf -- '---\ndescription: Gamma command\n---\nSay gamma.\n' > "$PLUGIN/commands/gamma.md"
  printf -- '---\nname: deep\ndescription: Deep skill\n---\nBody.\n' > "$PLUGIN/skills/deep/SKILL.md"
  printf -- '---\nname: demo\ndescription: >\n  Root skill\n---\nBody.\n' > "$PLUGIN/SKILL.md"
  jq -n --arg p "$PLUGIN" '{version: 2, plugins: {"demo@mkt": [{scope: "user", installPath: $p}]}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  write_settings '{"demo:alpha": "user-invocable-only", "demo:deep": "user-invocable-only", "demo:demo": "user-invocable-only", "demo:gamma": "name-only", "update-config": "user-invocable-only"}'
}

write_settings() {
  jq -n --argjson o "$1" '{skillOverrides: $o}' > "$CLAUDE_CONFIG_DIR/settings.json"
}

hidden() {
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit 1 } $0 == "disable-model-invocation: true" { found = 1; exit 0 } END { exit !found }' "$1"
}

@test "hides a plugin command set to user-invocable-only" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  hidden "$PLUGIN/commands/alpha.md"
  [ "$(sed -n 2p "$PLUGIN/commands/alpha.md")" = "disable-model-invocation: true" ]
  [ "$(tail -n 1 "$PLUGIN/commands/alpha.md")" = "Say alpha." ]
}

@test "hides a plugin skill in skills/<name>/SKILL.md" {
  run bash "$SCRIPT"
  hidden "$PLUGIN/skills/deep/SKILL.md"
}

@test "hides the root SKILL.md when its name matches" {
  run bash "$SCRIPT"
  hidden "$PLUGIN/SKILL.md"
}

@test "leaves a command that is not set or set to another value" {
  run bash "$SCRIPT"
  ! hidden "$PLUGIN/commands/beta.md"
  ! hidden "$PLUGIN/commands/gamma.md"
}

@test "leaves the root SKILL.md when its name is not set" {
  write_settings '{"demo:alpha": "user-invocable-only"}'
  run bash "$SCRIPT"
  ! hidden "$PLUGIN/SKILL.md"
}

@test "a second run adds no second line" {
  bash "$SCRIPT"
  bash "$SCRIPT"
  [ "$(grep -c '^disable-model-invocation:' "$PLUGIN/commands/alpha.md")" -eq 1 ]
}

@test "keeps a disable-model-invocation line that is already there" {
  printf -- '---\ndescription: Alpha command\ndisable-model-invocation: false\n---\nSay alpha.\n' > "$PLUGIN/commands/alpha.md"
  run bash "$SCRIPT"
  [ "$(grep -c '^disable-model-invocation:' "$PLUGIN/commands/alpha.md")" -eq 1 ]
  grep -q '^disable-model-invocation: false$' "$PLUGIN/commands/alpha.md"
}

@test "leaves a file with no frontmatter" {
  printf 'Say alpha.\nSay more.\n' > "$PLUGIN/commands/alpha.md"
  run bash "$SCRIPT"
  [ "$(cat "$PLUGIN/commands/alpha.md")" = "$(printf 'Say alpha.\nSay more.')" ]
}

@test "keeps the file mode" {
  chmod 640 "$PLUGIN/commands/alpha.md"
  bash "$SCRIPT"
  [ "$(ls -l "$PLUGIN/commands/alpha.md" | cut -c1-10)" = "-rw-r-----" ]
}

@test "prints nothing, so the hook adds no tokens to the session" {
  run bash "$SCRIPT"
  [ -z "$output" ]
}

@test "exits 0 with no output when the plugin list is missing" {
  rm "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 with no output when the settings are missing" {
  rm "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "leaves a command file that is a symlink" {
  printf -- '---\ndescription: Outside\n---\nSay outside.\n' > "$BATS_TEST_TMPDIR/outside.md"
  rm "$PLUGIN/commands/alpha.md"
  ln -s "$BATS_TEST_TMPDIR/outside.md" "$PLUGIN/commands/alpha.md"
  run bash "$SCRIPT"
  ! grep -q '^disable-model-invocation' "$BATS_TEST_TMPDIR/outside.md"
}

@test "leaves an install path outside the plugin cache" {
  OUT="$BATS_TEST_TMPDIR/dev/demo"
  mkdir -p "$OUT/commands"
  printf -- '---\ndescription: Alpha command\n---\nSay alpha.\n' > "$OUT/commands/alpha.md"
  jq -n --arg p "$OUT" '{version: 2, plugins: {"demo@mkt": [{scope: "user", installPath: $p}]}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$SCRIPT"
  ! hidden "$OUT/commands/alpha.md"
}

@test "ignores a name with a path in it" {
  mkdir -p "$PLUGIN/x"
  printf -- '---\ndescription: X\n---\nSay x.\n' > "$PLUGIN/x/evil.md"
  write_settings '{"demo:../x/evil": "user-invocable-only"}'
  run bash "$SCRIPT"
  ! hidden "$PLUGIN/x/evil.md"
}

@test "patches each install of the plugin" {
  P2="$CLAUDE_CONFIG_DIR/plugins/cache/mkt/demo/2.0.0"
  mkdir -p "$P2/commands"
  printf -- '---\ndescription: Alpha command\n---\nSay alpha.\n' > "$P2/commands/alpha.md"
  jq -n --arg a "$PLUGIN" --arg b "$P2" '{version: 2, plugins: {"demo@mkt": [{scope: "user", installPath: $a}, {scope: "project", installPath: $b}]}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$SCRIPT"
  hidden "$PLUGIN/commands/alpha.md"
  hidden "$P2/commands/alpha.md"
}

@test "leaves a plugin whose name only starts with the same text" {
  jq -n --arg p "$PLUGIN" '{version: 2, plugins: {"demo2@mkt": [{scope: "user", installPath: $p}]}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$SCRIPT"
  ! hidden "$PLUGIN/commands/alpha.md"
}

@test "skips an install path that does not exist" {
  jq -n --arg p "$CLAUDE_CONFIG_DIR/plugins/cache/mkt/demo/9.9.9" --arg q "$PLUGIN" '{version: 2, plugins: {"demo@mkt": [{scope: "user", installPath: $p}, {scope: "project", installPath: $q}]}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  hidden "$PLUGIN/commands/alpha.md"
}

@test "hides the root SKILL.md when its name is quoted" {
  printf -- '---\nname: "demo"\ndescription: Root skill\n---\nBody.\n' > "$PLUGIN/SKILL.md"
  run bash "$SCRIPT"
  hidden "$PLUGIN/SKILL.md"
}

@test "leaves a file with CRLF line ends" {
  printf -- '---\r\ndescription: Alpha command\r\n---\r\nSay alpha.\r\n' > "$PLUGIN/commands/alpha.md"
  run bash "$SCRIPT"
  ! grep -q '^disable-model-invocation' "$PLUGIN/commands/alpha.md"
}

@test "reads the old plugin list shape with one object per plugin" {
  jq -n --arg p "$PLUGIN" '{plugins: {"demo@mkt": {installPath: $p}}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$SCRIPT"
  hidden "$PLUGIN/commands/alpha.md"
}

@test "hides a command with no final newline" {
  printf -- '---\ndescription: Alpha command\n---\nSay alpha.' > "$PLUGIN/commands/alpha.md"
  run bash "$SCRIPT"
  hidden "$PLUGIN/commands/alpha.md"
  [ "$(tail -n 1 "$PLUGIN/commands/alpha.md")" = "Say alpha." ]
}
