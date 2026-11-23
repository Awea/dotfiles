#!/usr/bin/env bats
# dispatch.sh left: the work that is left for a task worker before a close. The /ok skill
# runs it. It checks the report and the worktrees that close removes, and changes nothing.

bats_require_minimum_version 1.5.0
load helper

O=block:01a1ef15-4833-735e-9530-226d79648a16

setup() {
  rex_setup
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$REPO" 2>/dev/null
  printf 'first\n' >"$REPO/README"
  git -C "$REPO" add README
  git -C "$REPO" commit -q -m first
  git -C "$REPO" push -q origin main
  git -C "$REPO" remote set-head origin main
  repo_with_push_policy "$REPO"
  printf 'Fix the login bug.\n' >"$BATS_TEST_TMPDIR/p.md"
  # The test repos are outside ~/.workspace: their worktrees go in _ext.
  WTS="$HOME/.workspace/.worktrees/_ext$BATS_TEST_TMPDIR"
  WT="$WTS/repo/fix-login"
  rex_orchestrator "$O" garden
}

# start_worker [CWD]: start a task worker and write its report. Sets W and REPORT.
start_worker() {
  run bash "$SKILL_DIR/dispatch.sh" start task "${1:-$REPO}" "Fix login" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  W=$(sed -n 1p <<<"$output")
  REPORT=$(sed -n 2p <<<"$output")
  printf 'RESULT: DONE\n' >"$REPORT"
}

left() { run --separate-stderr bash "$SKILL_DIR/dispatch.sh" left "$@"; }

@test "left prints nothing when the work is on the default branch" {
  start_worker
  [ -L "$WT/.claude/settings.local.json" ]
  left "$W"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "left gives a branch with commits that the default branch does not have, and keeps it" {
  start_worker
  git -C "$WT" commit -q --allow-empty -m work
  sha=$(git -C "$WT" rev-parse HEAD)
  left "$W"
  [ "$status" -eq 3 ]
  [ "$output" = "branch: fix-login of $REPO" ]
  [ -d "$WT" ]
  [ "$(git -C "$REPO" rev-parse fix-login)" = "$sha" ]
}

@test "left gives a worktree with changes that are not committed" {
  start_worker
  printf 'new\n' >"$WT/new.txt"
  left "$W"
  [ "$status" -eq 3 ]
  [ "$output" = "uncommitted: $WT" ]
  [ -f "$WT/new.txt" ]
}

@test "left gives a missing report" {
  start_worker
  rm "$REPORT"
  left "$W"
  [ "$status" -eq 3 ]
  [ "$output" = "report: none" ]
}

@test "left of a worker in a subfolder checks the worktree root" {
  mkdir -p "$REPO/sub"
  repo_with_push_policy "$REPO/sub"
  start_worker "$REPO/sub"
  [ -L "$WT/sub/.claude/settings.local.json" ]
  left "$W"
  [ "$status" -eq 0 ]
  printf 'new\n' >"$WT/top.txt"
  left "$W"
  [ "$status" -eq 3 ]
  [ "$output" = "uncommitted: $WT" ]
}

@test "left gives a detached HEAD that the default branch does not have" {
  start_worker
  git -C "$WT" checkout -q --detach
  git -C "$WT" commit -q --allow-empty -m work
  left "$W"
  [ "$status" -eq 3 ]
  [ "$output" = "detached: $WT" ]
}

@test "left checks the worktree of the card in another repo of the board" {
  v="$BATS_TEST_TMPDIR/vault"
  export OBSIDIAN_VAULT_PATH="$v"
  OTHER="$BATS_TEST_TMPDIR/api"
  git clone -q "$ORIGIN" "$OTHER" 2>/dev/null
  git -C "$OTHER" remote set-head origin main
  mkdir -p "$v/Boards" "$v/Projects"
  printf -- '---\nrepo: %s\n---\n' "$REPO" >"$v/Projects/card.md"
  printf -- '---\nrepo: %s\n---\n' "$OTHER" >"$v/Projects/api.md"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟢 **[card] Fix login**\n\tA. [[Projects/card]]\n- [ ] 🟢 **[api] One**\n\tB. [[Projects/api]]\n' >"$v/Boards/garden.md"
  start_worker
  git -C "$OTHER" worktree add -q -b fix-login "$WTS/api/fix-login" origin/HEAD
  left "$W"
  [ "$status" -eq 0 ]
  git -C "$WTS/api/fix-login" commit -q --allow-empty -m 'api work'
  left "$W"
  [ "$status" -eq 3 ]
  [ "$output" = "branch: fix-login of $OTHER" ]
}

@test "left takes the address from REX_BLOCK" {
  start_worker
  git -C "$WT" commit -q --allow-empty -m work
  REX_BLOCK="$W" run --separate-stderr bash "$SKILL_DIR/dispatch.sh" left
  [ "$status" -eq 3 ]
  [ "$output" = "branch: fix-login of $REPO" ]
}

@test "left fails for an address with no worker" {
  left block:00000000-0000-0000-0000-000000000000
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no worker in block:00000000-0000-0000-0000-000000000000"* ]]
}

@test "left fails for an auto worker" {
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  run bash "$SKILL_DIR/dispatch.sh" start auto "$REPO" "Check" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  left "$(sed -n 1p <<<"$output")"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"left runs only for a task worker"* ]]
}
