#!/usr/bin/env bats
# dispatch.sh start task: the worker claude starts in its own git worktree, so herdr-app
# and herdr-reviewr see the folder of its work.

bats_require_minimum_version 1.5.0
load helper

setup() {
  hc_setup
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$REPO" 2>/dev/null
  git -C "$REPO" commit -q --allow-empty -m first
  git -C "$REPO" push -q origin main
  git -C "$REPO" remote set-head origin main
  # The main checkout is on another branch, with a local commit: the worktree starts
  # from origin/HEAD, not from it.
  git -C "$REPO" checkout -q -b other
  git -C "$REPO" commit -q --allow-empty -m local
  repo_with_push_policy "$REPO"
  printf 'Fix the login bug.\n' >"$BATS_TEST_TMPDIR/p.md"
  WT="$BATS_TEST_TMPDIR/repo-fix-login"
  orchestrator t5 garden
}

start() { run bash "$SKILL_DIR/dispatch.sh" start "${1:-task}" "${2:-$REPO}" "${3:-Fix login}" "$BATS_TEST_TMPDIR/p.md"; }

@test "start task runs the worker in a new worktree beside the repo" {
  start
  [ "$status" -eq 0 ]
  run_args
  [ "$(arg_after --cwd)" = "$WT" ]
  [ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = fix-login ]
  [ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse origin/main)" ]
  [ "$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)" = "$REPO/.git" ]
}

@test "start task links the push policy of the repo into the worktree" {
  start
  [ "$status" -eq 0 ]
  [ -L "$WT/.claude/settings.local.json" ]
  [ "$(readlink "$WT/.claude/settings.local.json")" = "$REPO/.claude/settings.local.json" ]
}

@test "start task records the worktree, so resume opens it again" {
  start
  [ "$status" -eq 0 ]
  [ "$(cut -f6 "$XDG_STATE_HOME/board-orchestrator-hc/workers")" = "$WT" ]
}

@test "start task tells the worker its worktree, branch and repo" {
  start
  run_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"Your git worktree is $WT, on the branch fix-login."* ]]
  [[ "$prompt" == *"Change only the repo of your card: $REPO and its git worktrees."* ]]
}

@test "start task uses the worktree again for the same card" {
  start
  [ "$status" -eq 0 ]
  touch "$WT/work"
  start
  [ "$status" -eq 0 ]
  run_args 2
  [ "$(arg_after --cwd)" = "$WT" ]
  [ -f "$WT/work" ]
}

# Two card titles that give the same board slug: fix-login-bug-in-the-signup.
FORM="Fix login bug in the signup form"
PAGE="Fix login bug in the signup page"

@test "start task gives a card its own branch and worktree when another card has the same slug" {
  start task "$REPO" "$FORM"
  [ "$status" -eq 0 ]
  touch "$REPO-fix-login-bug-in-the-signup/form"
  start task "$REPO" "$PAGE"
  [ "$status" -eq 0 ]
  run_args 2
  [ "$(arg_after --cwd)" = "$REPO-fix-login-bug-in-the-signup-2" ]
  [ "$(git -C "$REPO-fix-login-bug-in-the-signup-2" rev-parse --abbrev-ref HEAD)" = fix-login-bug-in-the-signup-2 ]
  [ ! -e "$REPO-fix-login-bug-in-the-signup-2/form" ]
  [ "$(arg_after -n)" = fix-login-bug-in-the-signup-2 ]
  [[ "${RUN_ARGS[-1]}" == *"\"report fix-login-bug-in-the-signup-2 $XDG_STATE_HOME/board-orchestrator-hc/fix-login-bug-in-the-signup-2-"* ]]
  [ "$(tail -n 1 "$XDG_STATE_HOME/board-orchestrator-hc/workers" | cut -f7)" = fix-login-bug-in-the-signup-2 ]
}

@test "start task gives each card its slug again after another card took the next one" {
  start task "$REPO" "$FORM"
  start task "$REPO" "$PAGE"
  start task "$REPO" "$FORM"
  [ "$status" -eq 0 ]
  run_args 3
  [ "$(arg_after --cwd)" = "$REPO-fix-login-bug-in-the-signup" ]
  start task "$REPO" "$PAGE"
  [ "$status" -eq 0 ]
  run_args 4
  [ "$(arg_after --cwd)" = "$REPO-fix-login-bug-in-the-signup-2" ]
}

@test "start task gives a card its slug again when its title comes in another case or with other marks" {
  start task "$REPO" "$FORM"
  start task "$REPO" "fix login bug in the signup form. "
  [ "$status" -eq 0 ]
  run_args 2
  [ "$(arg_after --cwd)" = "$REPO-fix-login-bug-in-the-signup" ]
}

@test "start task finds a slug of another card in a long cards file" {
  mkdir -p "$XDG_STATE_HOME/board-orchestrator-hc"
  {
    printf 'fix-login\tanother-card\n'
    for i in $(seq 8000); do printf 'old-card-number-%s\told-card-number-%s\n' "$i" "$i"; done
  } >"$XDG_STATE_HOME/board-orchestrator-hc/cards"
  start
  [ "$status" -eq 0 ]
  run_args
  [ "$(arg_after --cwd)" = "$WT-2" ]
}

@test "start task gives the other repos of the board the slug of the card" {
  board_vault
  start task "$REPO" "$FORM"
  start task "$REPO" "$PAGE"
  [ "$status" -eq 0 ]
  run_args 2
  [[ "${RUN_ARGS[-1]}" == *"worktree add -b fix-login-bug-in-the-signup-2 $OTHER-fix-login-bug-in-the-signup-2 origin/HEAD,"* ]]
}

@test "start task takes another folder when the name is used by something else" {
  mkdir -p "$WT"
  start
  [ "$status" -eq 0 ]
  run_args
  [ "$(arg_after --cwd)" = "$WT-2" ]
  [ "$(git -C "$WT-2" rev-parse --abbrev-ref HEAD)" = fix-login ]
}

@test "start task checks out a branch of the card that exists" {
  git -C "$REPO" branch fix-login origin/main
  git -C "$REPO" commit -q --allow-empty -m more
  git -C "$REPO" branch -f fix-login HEAD
  git -C "$REPO" checkout -q other
  start
  [ "$status" -eq 0 ]
  [ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse fix-login)" ]
}

@test "start task in a linked worktree makes no other worktree" {
  git -C "$REPO" worktree add -q -b mine "$BATS_TEST_TMPDIR/mine" origin/main
  repo_with_push_policy "$BATS_TEST_TMPDIR/mine"
  start task "$BATS_TEST_TMPDIR/mine"
  [ "$status" -eq 0 ]
  run_args
  [ "$(arg_after --cwd)" = "$BATS_TEST_TMPDIR/mine" ]
  [ ! -e "$WT" ]
}

@test "start auto runs in the repo, with no worktree" {
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  [ "$status" -eq 0 ]
  run_args
  [ "$(arg_after --cwd)" = "$REPO" ]
  [ ! -e "$WT" ]
}

@test "start task loads the direnv environment of the main checkout" {
  printf 'use flake\n' >"$REPO/.envrc"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/bin/direnv"
  chmod +x "$BATS_TEST_TMPDIR/bin/direnv"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" start
  [ "$status" -eq 0 ]
  run_args
  [ "$(arg_after direnv)" = exec ]
  [ "$(arg_after exec)" = "$REPO" ]
}

@test "start task fails and starts nothing when git cannot make the worktree" {
  # A file in place of the worktrees folder of git.
  touch "$REPO/.git/worktrees"
  start
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not make a worktree"* ]]
  [ -z "$(calls '^hc run')" ]
}

# board_vault: a vault whose board garden links the card repo, another git repo of the
# board (api, ask policy), a plain folder (notes) and a missing folder (gone). The board
# work links a repo of another board only.
board_vault() {
  local v="$BATS_TEST_TMPDIR/vault"
  export OBSIDIAN_VAULT_PATH="$v"
  OTHER="$BATS_TEST_TMPDIR/api"
  git clone -q "$ORIGIN" "$OTHER" 2>/dev/null
  git -C "$OTHER" remote set-head origin main
  mkdir -p "$OTHER/.claude" "$BATS_TEST_TMPDIR/notes" "$BATS_TEST_TMPDIR/work/.git" "$v/Boards" "$v/Projects"
  printf '{"permissions":{"ask":["Bash(git push*)"]}}\n' >"$OTHER/.claude/settings.local.json"
  printf -- '---\nrepo: %s\n---\n' "$REPO" >"$v/Projects/card.md"
  printf -- '---\nrepo: "%s"\n---\n' "$OTHER" >"$v/Projects/api.md"
  printf -- '---\nrepo: %s\n---\n' "$BATS_TEST_TMPDIR/notes" >"$v/Projects/notes.md"
  printf -- '---\nrepo: %s\n---\n' "$BATS_TEST_TMPDIR/gone" >"$v/Projects/gone.md"
  printf -- '---\nrepo: %s\n---\n' "$BATS_TEST_TMPDIR/work" >"$v/Projects/work.md"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟢 **[card] Fix login**\n\tA. [[Projects/card]]\n- [ ] 🟢 **[api] One**\n\tB. [[Projects/api]]\n- [ ] 🟢 **[api] Two**\n\tC. [[Projects/api|the api]]\n- [ ] 🟢 **[notes] N**\n\t[[Projects/notes]] [[Projects/gone]]\n' >"$v/Boards/garden.md"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟢 **[work] W**\n\t[[Projects/work]]\n' >"$v/Boards/work.md"
}

@test "start task lets the worker change the other git repos of its board" {
  board_vault
  start
  [ "$status" -eq 0 ]
  run_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"Change only the repo of your card: $REPO and its git worktrees, and the other repos of your board below. When the work needs a repo that is not in that list, do not change that repo: stop that work."* ]]
  [[ "$prompt" == *"The other repos of your board: $OTHER (push policy ask, worktree $OTHER-fix-login)."* ]]
  [[ "$prompt" == *"run git -C $OTHER worktree add -b fix-login $OTHER-fix-login origin/HEAD, or use that worktree when it exists."* ]]
  [[ "$prompt" == *"Follow the push policy of that repo, not the policy of your card: allow, push and open a PR; ask, ask the user before each push and each PR; deny, missing or invalid, do not push"* ]]
  [ "$(grep -o "$OTHER " <<<"$prompt" | wc -l)" -eq 2 ]
  [[ "$prompt" != *"$BATS_TEST_TMPDIR/notes"* ]]
  [[ "$prompt" != *"$BATS_TEST_TMPDIR/gone"* ]]
  [[ "$prompt" != *"$BATS_TEST_TMPDIR/work"* ]]
  [[ "$prompt" != *"$REPO (push policy"* ]]
}

@test "start task gives HEAD as the base of a repo with no origin/HEAD" {
  board_vault
  git -C "$OTHER" remote set-head origin -d
  start
  [ "$status" -eq 0 ]
  run_args
  [[ "${RUN_ARGS[-1]}" == *"worktree add -b fix-login $OTHER-fix-login HEAD,"* ]]
}

@test "start task from a linked worktree does not list the card repo as another repo" {
  board_vault
  git -C "$REPO" worktree add -q -b mine "$BATS_TEST_TMPDIR/mine" origin/main
  repo_with_push_policy "$BATS_TEST_TMPDIR/mine"
  start task "$BATS_TEST_TMPDIR/mine"
  [ "$status" -eq 0 ]
  run_args
  [[ "${RUN_ARGS[-1]}" != *"$REPO (push policy"* ]]
  [[ "${RUN_ARGS[-1]}" == *"$OTHER (push policy ask"* ]]
}

@test "start task with no other repo on the board keeps the worker in its repo" {
  board_vault
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟢 **[card] Fix login**\n\tA. [[Projects/card]]\n' >"$OBSIDIAN_VAULT_PATH/Boards/garden.md"
  start
  [ "$status" -eq 0 ]
  run_args
  [[ "${RUN_ARGS[-1]}" == *"Change only the repo of your card: $REPO and its git worktrees. When the work needs another repo"* ]]
  [[ "${RUN_ARGS[-1]}" != *"other repos of your board"* ]]
}

@test "start auto gives no other repo of the board" {
  board_vault
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  start auto
  [ "$status" -eq 0 ]
  run_args
  [[ "${RUN_ARGS[-1]}" != *"other repos of your board"* ]]
}
