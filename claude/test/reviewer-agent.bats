#!/usr/bin/env bats
# Tests for the reviewer agent type (claude/agents/reviewer.md) and its link.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
AGENT="$REPO/claude/agents/reviewer.md"

# frontmatter: the lines between the first two --- lines of the agent file
frontmatter() { awk '/^---$/ { n++; next } n == 1' "$AGENT"; }

@test "make links the reviewer agent" {
  run make -n -C "$REPO" HOME="$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/.claude/agents/reviewer.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s $REPO/claude/agents/reviewer.md $BATS_TEST_TMPDIR/.claude/agents/reviewer.md"* ]]
}

@test "the links target holds the reviewer agent" {
  grep -q '^links:.*\$(HOME)/\.claude/agents/reviewer\.md' "$REPO/Makefile"
}

@test "the reviewer agent has its model, effort and read-only tools" {
  run frontmatter
  [ "$status" -eq 0 ]
  grep -qx 'name: reviewer' <<<"$output"
  grep -qx 'model: opus' <<<"$output"
  grep -qx 'effort: high' <<<"$output"
  tools=$(grep '^tools:' <<<"$output")
  for t in Read Grep Glob Bash; do [[ "$tools" == *"$t"* ]] || return 1; done
  for t in Edit Write NotebookEdit; do [[ "$tools" != *"$t"* ]] || return 1; done
}

@test "the reviewer writes no findings only when nothing is open" {
  grep -q 'When no old finding is open and you have no new finding, write only `no findings`' "$AGENT"
  grep -q 'The main agent can reject a finding with a reason' "$AGENT"
}

@test "the global rules keep the final review and run the reviewr loop only on request" {
  rules="$REPO/claude/CLAUDE.md"
  grep -q 'Run a final whole-branch review before a merge or a push' "$rules"
  grep -q 'Run the review loop only when the user asks for it' "$rules"
  grep -q 'is the final whole-branch review of a superpowers skill: run it once' "$rules"
  grep -q '^description: .*When the user asks for the review loop, send each new range' "$AGENT"
  grep -q 'presses `B`, types the short SHA of the base commit' "$rules"
  grep -q 'hc label "$HC_TERMINAL_ID" reviewr.dir=<worktree root> reviewr.base=<short base SHA>' "$rules"
  run grep -q 'replaces the final whole-branch review of a superpowers skill' "$rules"
  [ "$status" -eq 1 ]
  grep -q 'send the rejected findings with their reasons' "$rules"
  grep -q 'Run the Fable review only when the user asks for it' "$rules"
  run grep -q 'in the same turn as the work' "$rules"
  [ "$status" -eq 1 ]
}
