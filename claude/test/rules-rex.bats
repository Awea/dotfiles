#!/usr/bin/env bats
# Tests for the Rex rules in claude/CLAUDE.md.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

rules="$BATS_TEST_DIRNAME/../CLAUDE.md"

@test "the Rex block starts with its Renux condition, and says what to do outside Renux" {
  grep -qF 'In Renux (`REX_BLOCK` set), use these rules.' "$rules"
  grep -qF 'Outside Renux, run a slow command as a background Bash call' "$rules"
}

@test "the Rex block has the rex run line" {
  grep -qF 'rex run -s "$REX_SESSION" --focus=false --keep-open --interactive --label <n> --cwd <dir> --json -- ~/.bin/when-free <cmd>' "$rules"
}

@test "the Rex block has the rex wait line" {
  grep -qF 'rex wait <block> --for 110s --json' "$rules"
}

@test "the Rex block has the rex capture line" {
  grep -qF 'rex capture -b <block> --trim | tail -40' "$rules"
}

@test "the Rex block has the rex block close line" {
  grep -qF 'rex block close <block>' "$rules"
}

@test "the Rex block has the rex-resource line" {
  grep -qF '~/.bin/rex-resource <n> <dir> -- <cmd>' "$rules"
}

@test "the Rex block has the reviewr-target line" {
  grep -qF '~/.config/rex/bin/reviewr-target <worktree root> <short base SHA>' "$rules"
}

@test "the Rex block keeps the block ID, waits again, keeps shared resources, names tabs" {
  grep -qF 'not the label' "$rules"
  grep -qF 'On a time-out, wait again.' "$rules"
  grep -qF 'Do not close a shared resource' "$rules"
  grep -qF 'tab name' "$rules"
}

@test "no hc or herdr-app rule is left" {
  run grep -nE '`hc |hc (run|wait|read|label|get)|HC_TERMINAL_ID|herdr-app' "$rules"
  [ "$status" -eq 1 ]
}

@test "no rex rule uses --focus without =false" {
  run bash -c "grep -n 'rex run' '$rules' | grep -v -- '--focus=false'"
  [ "$output" = "" ]
}

@test "the Rex block tells a time-out from the end of the command, names jobs, reads a resource" {
  grep -qF '{"exit_code":N,…}' "$rules"
  grep -qF 'A time-out prints no JSON' "$rules"
  grep -qF 'for example `shop323-test`, never `fix` or `test`' "$rules"
  grep -qF '`rex capture -s <session> -b <block> --trim | tail -40`. Do not close a shared resource.' "$rules"
}

@test "the reviewr and job name bullets use the Renux condition" {
  grep -qF 'In Renux (`REX_BLOCK` set), first run' "$rules"
  grep -qF 'Outside Renux, give the short SHA of the base' "$rules"
  grep -qF -- '- In Renux, write the tab name of a job, not its block ID.' "$rules"
}

@test "the Rex block has the rex-tab-name line" {
  grep -qF '~/.bin/rex-tab-name <branch>' "$rules"
  grep -qF 'A board worker skips it' "$rules"
}

@test "the Rex block has the rex-summary line" {
  grep -qF '~/.bin/rex-summary "<sentence>"' "$rules"
  grep -qF 'A subagent skips it' "$rules"
}

@test "the Rex block has the branches-open line" {
  grep -qF '~/.config/rex/bin/branches-open <repo>' "$rules"
}

@test "the Replies block writes a block ID as a renux block link" {
  grep -qF '[e0760707](renux://block/e0760707)' "$rules"
}
