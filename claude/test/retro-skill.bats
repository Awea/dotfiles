#!/usr/bin/env bats
# Tests for the retro skill (claude/skills/retro/SKILL.md) and its link.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SKILL="$REPO/claude/skills/retro/SKILL.md"

@test "make links the retro skill" {
  run make -n -C "$REPO" PWD="$REPO" HOME="$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/.claude/skills/retro"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s $REPO/claude/skills/retro $BATS_TEST_TMPDIR/.claude/skills/retro"* ]]
}

@test "the links target holds the retro skill" {
  grep -q '^links:.*\$(HOME)/\.claude/skills/retro\b' "$REPO/Makefile"
}

@test "the retro skill is user-invoked and gives its source" {
  grep -qx 'disable-model-invocation: true' "$SKILL"
  grep -q '^<!-- Source: https://github.com/mattpocock/skills/blob/[0-9a-f]\{40\}/skills/engineering/retro/SKILL.md (MIT, Matt Pocock) -->' "$SKILL"
}

# writing-for-agents is user-invoked here, so the Skill tool cannot load it.
@test "retro reads the writing-for-agents guide as a file" {
  grep -q 'Read `~/.claude/skills/writing-for-agents/SKILL.md`' "$SKILL"
  run grep -q 'Call the Skill tool with `writing-for-agents`' "$SKILL"
  [ "$status" -eq 1 ]
}
