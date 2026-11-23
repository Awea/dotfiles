#!/usr/bin/env bats
# Tests for the plugin-file-overrides SessionStart hook (claude/hooks/plugin-file-overrides.sh),
# the override files (claude/plugin-overrides/) and their links.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HOOK="$REPO/claude/hooks/plugin-file-overrides.sh"

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  cache="$CLAUDE_CONFIG_DIR/plugins/cache/market/superpowers"
  mkdir -p "$CLAUDE_CONFIG_DIR/plugin-overrides/superpowers/skills/using-superpowers" \
    "$cache/1.0.0/skills/using-superpowers" "$cache/1.0.1/skills/using-superpowers"
  printf 'new\n' > "$CLAUDE_CONFIG_DIR/plugin-overrides/superpowers/skills/using-superpowers/SKILL.md"
  printf 'old\n' > "$cache/1.0.0/skills/using-superpowers/SKILL.md"
  printf 'old\n' > "$cache/1.0.1/skills/using-superpowers/SKILL.md"
  cat > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" <<EOF
{ "plugins": {
  "superpowers@market": [
    { "installPath": "$cache/1.0.0" },
    { "installPath": "$cache/1.0.1" }
  ],
  "other@market": [ { "installPath": "$CLAUDE_CONFIG_DIR/plugins/cache/market/other/1.0.0" } ]
} }
EOF
}

@test "the hook copies an override over each installed version" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$cache/1.0.0/skills/using-superpowers/SKILL.md")" = new ]
  [ "$(cat "$cache/1.0.1/skills/using-superpowers/SKILL.md")" = new ]
}

@test "the hook skips an override with no file in the plugin" {
  mkdir -p "$CLAUDE_CONFIG_DIR/plugin-overrides/superpowers/skills/gone"
  printf 'new\n' > "$CLAUDE_CONFIG_DIR/plugin-overrides/superpowers/skills/gone/SKILL.md"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ ! -e "$cache/1.0.0/skills/gone" ]
}

@test "the hook writes no file through a symlink" {
  printf 'outside\n' > "$BATS_TEST_TMPDIR/outside"
  ln -sf "$BATS_TEST_TMPDIR/outside" "$cache/1.0.0/skills/using-superpowers/SKILL.md"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/outside")" = outside ]
}

@test "the hook writes no file through a symlinked folder" {
  mkdir -p "$BATS_TEST_TMPDIR/out"
  printf 'old\n' > "$BATS_TEST_TMPDIR/out/SKILL.md"
  rm -rf "$cache/1.0.0/skills/using-superpowers"
  ln -s "$BATS_TEST_TMPDIR/out" "$cache/1.0.0/skills/using-superpowers"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/out/SKILL.md")" = old ]
}

@test "the hook leaves a file that already matches" {
  printf 'new\n' > "$cache/1.0.0/skills/using-superpowers/SKILL.md"
  before=$(ls -i "$cache/1.0.0/skills/using-superpowers/SKILL.md")
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(ls -i "$cache/1.0.0/skills/using-superpowers/SKILL.md")" = "$before" ]
}

@test "the hook leaves a plugin whose name only starts with the override name" {
  lab="$CLAUDE_CONFIG_DIR/plugins/cache/market/superpowers-lab/1.0.0"
  mkdir -p "$lab/skills/using-superpowers"
  printf 'old\n' > "$lab/skills/using-superpowers/SKILL.md"
  jq --arg p "$lab" '.plugins["superpowers-lab@market"] = [{ installPath: $p }]' \
    "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$BATS_TEST_TMPDIR/i.json"
  mv "$BATS_TEST_TMPDIR/i.json" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(cat "$lab/skills/using-superpowers/SKILL.md")" = old ]
}

@test "the hook keeps the mode of the plugin file" {
  chmod 640 "$cache/1.0.0/skills/using-superpowers/SKILL.md"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(ls -l "$cache/1.0.0/skills/using-superpowers/SKILL.md" | cut -c1-10)" = "-rw-r-----" ]
}

@test "the hook writes no file outside the plugin cache" {
  outside="$BATS_TEST_TMPDIR/elsewhere/superpowers"
  mkdir -p "$outside/skills/using-superpowers"
  printf 'old\n' > "$outside/skills/using-superpowers/SKILL.md"
  jq --arg p "$outside" '.plugins["superpowers@market"] = [{ installPath: $p }]' \
    "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$BATS_TEST_TMPDIR/i.json"
  mv "$BATS_TEST_TMPDIR/i.json" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(cat "$outside/skills/using-superpowers/SKILL.md")" = old ]
}

@test "the hook exits 0 with no override folder" {
  rm -rf "$CLAUDE_CONFIG_DIR/plugin-overrides"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "make links the hook and the override folder" {
  run make -n -C "$REPO" PWD="$REPO" HOME="$BATS_TEST_TMPDIR" \
    "$BATS_TEST_TMPDIR/.claude/hooks/plugin-file-overrides.sh" "$BATS_TEST_TMPDIR/.claude/plugin-overrides"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s $REPO/claude/hooks/plugin-file-overrides.sh $BATS_TEST_TMPDIR/.claude/hooks/plugin-file-overrides.sh"* ]]
  [[ "$output" == *"ln -s $REPO/claude/plugin-overrides $BATS_TEST_TMPDIR/.claude/plugin-overrides"* ]]
}

@test "the links target holds the hook and the override folder" {
  grep -q '^links:.*\$(HOME)/\.claude/hooks/plugin-file-overrides\.sh' "$REPO/Makefile"
  grep -q '^links:.*\$(HOME)/\.claude/plugin-overrides\b' "$REPO/Makefile"
}

@test "settings.json runs the hook at session start" {
  jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("plugin-file-overrides\\.sh"))' "$REPO/claude/settings.json"
}

@test "the using-superpowers override is user-invoked" {
  skill="$REPO/claude/plugin-overrides/superpowers/skills/using-superpowers/SKILL.md"
  grep -qx 'name: using-superpowers' "$skill"
  grep -qx 'disable-model-invocation: true' "$skill"
}
