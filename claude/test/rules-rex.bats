#!/usr/bin/env bats
# Tests for the Rex rules in claude/CLAUDE.md.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

rules="$BATS_TEST_DIRNAME/../CLAUDE.md"

@test "the Rex block starts with its Renux condition" {
  grep -qF 'In Renux (`REX_BLOCK` set and `HC_TERMINAL_ID` not set), use these rules in place of the `hc` rules above.' "$rules"
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

@test "the hc rules are unchanged" {
  grep -qF 'hc run --bg --no-notify --name <n> --cwd <dir> -- <cmd>' "$rules"
  grep -qF 'hc wait <n> --timeout 110' "$rules"
  grep -qF 'hc run --bg --no-parent --no-notify --name <n> --cwd <dir> -- <cmd>' "$rules"
  grep -qF 'hc label "$HC_TERMINAL_ID" reviewr.dir=<worktree root> reviewr.base=<short base SHA>' "$rules"
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

@test "the reviewr and address bullets use the Renux condition of the Rex block" {
  grep -qF -- '- In Renux (`REX_BLOCK` set and `HC_TERMINAL_ID` not set), in place of the `hc label` step' "$rules"
  grep -qF '  and of the `b`/`B` steps, run' "$rules"
  grep -qF -- '- In Renux (`REX_BLOCK` set and `HC_TERMINAL_ID` not set), write the tab name of a job' "$rules"
}
