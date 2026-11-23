#!/usr/bin/env bats
# Tests for the ok skill (claude/skills/ok/SKILL.md) and its link. /ok closes a board
# worker when no work is left.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SKILL="$REPO/claude/skills/ok/SKILL.md"

@test "make links the ok skill" {
  run make -n -C "$REPO" PWD="$REPO" HOME="$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/.claude/skills/ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s $REPO/claude/skills/ok $BATS_TEST_TMPDIR/.claude/skills/ok"* ]]
}

@test "the links target holds the ok skill" {
  grep -q '^links:.*\$(HOME)/\.claude/skills/ok\b' "$REPO/Makefile"
}

@test "the ok skill is user-invoked" {
  grep -qx 'name: ok' "$SKILL"
  grep -qx 'disable-model-invocation: true' "$SKILL"
}

# A worker claude has an allow rule only for dispatch.sh tell.
@test "the ok skill allows dispatch.sh left" {
  grep -qx 'allowed-tools: Bash(bash ~/.claude/skills/board-orchestrator/dispatch.sh left)' "$SKILL"
  grep -qF '`bash ~/.claude/skills/board-orchestrator/dispatch.sh left`' "$SKILL"
}

@test "the ok skill asks Close anyway?" {
  grep -qF 'Close anyway?' "$SKILL"
}

# The worker allow rule for tell has the absolute path of the first prompt: a command with
# ~ does not match it, and Claude asks for a permission.
@test "the ok skill closes with the exact close command of the first prompt" {
  grep -qF 'run the close command of your first prompt, exactly as it is' "$SKILL"
  run grep -F 'dispatch.sh tell' "$SKILL"
  [ "$status" -eq 1 ]
}

@test "the ok skill keeps an open PR when the card stays open or has a follow-up" {
  grep -qF 'RESULT: WAITS FOR USER' "$SKILL"
  grep -qF '## Vault changes' "$SKILL"
}

@test "the ok skill does not do the remaining work" {
  grep -qi 'do not rebase, push or merge' "$SKILL"
}
