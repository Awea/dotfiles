#!/usr/bin/env bats
# Tests for the grilling, domain-modeling and prototype skills of mattpocock/skills
# (claude/skills/<name>/) and their links.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SKILLS="grilling domain-modeling prototype"

# The upstream folder of each skill in mattpocock/skills.
upstream_dir() {
  case "$1" in
    grilling) echo productivity/grilling ;;
    *) echo "engineering/$1" ;;
  esac
}

@test "make links each skill" {
  for name in $SKILLS; do
    run make -n -C "$REPO" PWD="$REPO" HOME="$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/.claude/skills/$name"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ln -s $REPO/claude/skills/$name $BATS_TEST_TMPDIR/.claude/skills/$name"* ]]
  done
}

@test "the links target holds each skill" {
  for name in $SKILLS; do
    grep -q "^links:.*\$(HOME)/\.claude/skills/$name\b" "$REPO/Makefile"
  done
}

@test "each skill is user-invoked and gives its source" {
  for name in $SKILLS; do
    skill="$REPO/claude/skills/$name/SKILL.md"
    grep -qx "name: $name" "$skill"
    grep -qx 'disable-model-invocation: true' "$skill"
    grep -q "^<!-- Source: https://github.com/mattpocock/skills/blob/[0-9a-f]\{40\}/skills/$(upstream_dir "$name")/SKILL.md (MIT, Matt Pocock) -->" "$skill"
  done
}

# The local files each SKILL.md links to, in the order of the text.
expected_links() {
  case "$1" in
    domain-modeling) echo "GLOSSARY-FORMAT.md ADR-FORMAT.md" ;;
    prototype) echo "LOGIC.md UI.md" ;;
  esac
}

@test "each file a skill links to exists" {
  for name in $SKILLS; do
    dir="$REPO/claude/skills/$name"
    [ -f "$dir/SKILL.md" ]
    targets=$(grep -oE '\]\((\./)?[A-Z-]+\.md\)' "$dir/SKILL.md" | sed -E 's/^\]\((\.\/)?//; s/\)$//' | tr '\n' ' ' | sed 's/ $//' || true)
    [ "$targets" = "$(expected_links "$name")" ]
    for target in $targets; do
      [ -f "$dir/$target" ]
    done
  done
}

@test "domain-modeling and prototype have their support files" {
  [ -f "$REPO/claude/skills/domain-modeling/GLOSSARY-FORMAT.md" ]
  [ -f "$REPO/claude/skills/domain-modeling/ADR-FORMAT.md" ]
  [ -f "$REPO/claude/skills/prototype/LOGIC.md" ]
  [ -f "$REPO/claude/skills/prototype/UI.md" ]
}
