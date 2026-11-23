#!/usr/bin/env bats
# dispatch.sh close of a task worker: it runs make worktree-teardown, removes the worktree
# of the card and deletes its branch when the default branch has all its commits. A done
# worker keeps its worktree until the close: the user can still refuse the changes.

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
  # The teardown recipe writes the folder it ran in, and if the worktree was still there.
  printf 'worktree-teardown:\n\t@if [ -e .git ]; then echo "$$(pwd -P) with git"; else echo "$$(pwd -P) no git"; fi >>%s\n' \
    "$BATS_TEST_TMPDIR/teardown-ran" >"$REPO/Makefile"
  git -C "$REPO" add Makefile
  git -C "$REPO" commit -q -m first
  git -C "$REPO" push -q origin main
  git -C "$REPO" remote set-head origin main
  repo_with_push_policy "$REPO"
  printf 'Fix the login bug.\n' >"$BATS_TEST_TMPDIR/p.md"
  # The test repos are outside ~/.workspace: their worktrees go in _ext.
  WTS="$HOME/.workspace/.worktrees/_ext$BATS_TEST_TMPDIR"
  WT="$WTS/repo/fix-login"
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  rex_orchestrator "$O" garden
}

# start_worker [CWD]: start a task worker, write its report, and make it idle. Sets W and
# REPORT.
start_worker() {
  run bash "$SKILL_DIR/dispatch.sh" start task "${1:-$REPO}" "Fix login" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  W=$(sed -n 1p <<<"$output")
  REPORT=$(sed -n 2p <<<"$output")
  printf 'RESULT: DONE\n' >"$REPORT"
  rex_status "$W" idle
}

close() { run --separate-stderr bash "$SKILL_DIR/dispatch.sh" close "$W"; }

# gone BLOCK: the block of the worker is gone, as after a stop of the orchestrator.
gone() {
  grep -v -F "\"block_id\":\"$1\"" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp" || true
  mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"
}

resume_clear() { run --separate-stderr bash "$SKILL_DIR/dispatch.sh" resume-clear garden; }

@test "start task does not tell the worker to remove its worktree" {
  start_worker
  rex_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-window-new-1.args"; }
  rex_args
  [[ "${RUN_ARGS[-1]}" != *"worktree remove"* ]]
  [[ "${RUN_ARGS[-1]}" == *"Do not remove your worktree or its branch: the orchestrator removes them when it closes you."* ]]
}

@test "close runs make worktree-teardown in the worktree, then removes it" {
  start_worker
  [ -d "$WT" ]
  session=$(cut -f5 "$STATE/workers")
  close
  [ "$status" -eq 0 ]
  [ "$output" = "$session" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
  [ ! -e "$WT" ]
  [ -z "$(git -C "$REPO" worktree list | grep -F "$WT" || true)" ]
  grep -q "make worktree-teardown in $WT" "${REPORT%.md}-worktree-teardown.log"
}

@test "close runs the teardown in the direnv env of the main checkout" {
  # The fake direnv logs its call, then runs the command after "exec DIR". lib.sh puts
  # ~/.local/bin first on PATH.
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\nprintf "direnv %%s\\n" "$*" >>"$FAKE_LOG"\nshift 2\nexec "$@"\n' >"$HOME/.local/bin/direnv"
  chmod +x "$HOME/.local/bin/direnv"
  start_worker
  : >"$REPO/.envrc"
  close
  [ "$status" -eq 0 ]
  [ -n "$(calls "^direnv exec $REPO make -C $WT worktree-teardown")" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
  [ ! -e "$WT" ]
}

@test "close deletes the branch when the default branch has all its commits" {
  start_worker
  close
  [ "$status" -eq 0 ]
  ! git -C "$REPO" show-ref -q --verify refs/heads/fix-login
}

@test "close keeps a branch with commits that the default branch does not have" {
  start_worker
  git -C "$WT" commit -q --allow-empty -m work
  sha=$(git -C "$WT" rev-parse HEAD)
  close
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
  [ "$(git -C "$REPO" rev-parse fix-login)" = "$sha" ]
  [[ "$stderr" == *"kept the branch fix-login of $REPO"* ]]
}

@test "close deletes a renamed branch that the local default branch has" {
  start_worker
  git -C "$WT" branch -m login-fix
  git -C "$WT" commit -q --allow-empty -m work
  git -C "$REPO" checkout -q main
  git -C "$REPO" merge -q --ff-only login-fix
  git -C "$REPO" checkout -q -b other
  close
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
  ! git -C "$REPO" show-ref -q --verify refs/heads/login-fix
}

@test "close keeps a worktree with changes that are not committed, and runs its teardown" {
  start_worker
  printf 'draft\n' >"$WT/draft.txt"
  close
  [ "$status" -eq 0 ]
  [ -f "$WT/draft.txt" ]
  [ -L "$WT/.claude/settings.local.json" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
  git -C "$REPO" show-ref -q --verify refs/heads/fix-login
  [[ "$stderr" == *"kept the worktree $WT: it has changes that are not committed"* ]]
}

@test "close keeps the worktree when make worktree-teardown fails" {
  start_worker
  printf 'worktree-teardown:\n\t@echo db busy; exit 3\n' >"$WT/Makefile"
  git -C "$WT" commit -q -am broken
  close
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  git -C "$REPO" show-ref -q --verify refs/heads/fix-login
  [[ "$stderr" == *"kept the worktree $WT: make worktree-teardown failed"* ]]
  grep -q 'db busy' "${REPORT%.md}-worktree-teardown.log"
}

@test "close removes a worktree with no teardown target" {
  start_worker
  git -C "$WT" rm -q Makefile
  git -C "$WT" commit -q -m 'no make'
  close
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
  [ ! -e "$BATS_TEST_TMPDIR/teardown-ran" ]
}

@test "close keeps the worktree of a worker with no report, and runs its teardown" {
  start_worker
  rm "$REPORT"
  close
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
  [[ "$stderr" == *"kept the worktree $WT: the worker wrote no report"* ]]
}

@test "close of a worker in a subfolder removes the worktree root" {
  mkdir -p "$REPO/sub"
  repo_with_push_policy "$REPO/sub"
  start_worker "$REPO/sub"
  [ -L "$WT/sub/.claude/settings.local.json" ]
  close
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
}

@test "close keeps a linked worktree that start did not make" {
  git -C "$REPO" worktree add -q -b mine "$BATS_TEST_TMPDIR/mine" origin/main
  repo_with_push_policy "$BATS_TEST_TMPDIR/mine"
  start_worker "$BATS_TEST_TMPDIR/mine"
  close
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/mine" ]
  [ ! -e "$BATS_TEST_TMPDIR/teardown-ran" ]
  git -C "$REPO" show-ref -q --verify refs/heads/mine
}

# other_repo_close WT: close removes the worktree WT of the card in another repo of the
# board.
other_repo_close() {
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
  git -C "$OTHER" worktree add -q -b fix-login "$1" origin/HEAD
  git -C "$1" commit -q --allow-empty -m 'api work'
  close
  [ "$status" -eq 0 ]
  [ ! -e "$1" ]
  [ "$(sort "$BATS_TEST_TMPDIR/teardown-ran")" = "$(printf '%s with git\n%s with git' "$1" "$WT" | sort)" ]
  git -C "$OTHER" show-ref -q --verify refs/heads/fix-login
  [[ "$stderr" == *"kept the branch fix-login of $OTHER"* ]]
}

@test "close removes the worktree of the card in another repo of the board" {
  other_repo_close "$WTS/api/fix-login"
}

@test "close removes the worktree of the card in another repo with the old path beside the repo" {
  other_repo_close "$BATS_TEST_TMPDIR/api-fix-login"
}

@test "close removes the worktree of a repo of a linked ~/.workspace and its empty folders" {
  mkdir -p "$BATS_TEST_TMPDIR/ws/org"
  ln -s "$BATS_TEST_TMPDIR/ws" "$HOME/.workspace"
  APP="$BATS_TEST_TMPDIR/ws/org/app"
  git clone -q "$ORIGIN" "$APP" 2>/dev/null
  git -C "$APP" remote set-head origin main
  repo_with_push_policy "$APP"
  start_worker "$HOME/.workspace/org/app"
  wt="$BATS_TEST_TMPDIR/ws/.worktrees/org/app/fix-login"
  [ -d "$wt" ]
  mkdir -p "$BATS_TEST_TMPDIR/ws/.worktrees/other"
  close
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$wt with git" ]
  [ ! -e "$BATS_TEST_TMPDIR/ws/.worktrees/org" ]
  [ -d "$BATS_TEST_TMPDIR/ws/.worktrees/other" ]
}

@test "close removes a worktree with the old path beside the repo" {
  old="$REPO-fix-login"
  git -C "$REPO" worktree add -q -b fix-login "$old" origin/HEAD
  mkdir -p "$old/.claude"
  ln -s "$REPO/.claude/settings.local.json" "$old/.claude/settings.local.json"
  start_worker "$old"
  close
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$old with git" ]
  [ ! -e "$old" ]
}

@test "close of an auto worker removes no folder" {
  printf '{"permissions":{"allow":["Bash(make test)"]}}\n' >"$REPO/.claude/settings.readonly.json"
  run bash "$SKILL_DIR/dispatch.sh" start auto "$REPO" "Check" "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  W=$(sed -n 1p <<<"$output")
  printf 'STATUS: OK\n' >"$(sed -n 2p <<<"$output")"
  rex_status "$W" idle
  close
  [ "$status" -eq 0 ]
  [ -d "$REPO" ]
  [ ! -e "$BATS_TEST_TMPDIR/teardown-ran" ]
}

@test "close that gives up while the worker works keeps the worktree" {
  start_worker
  rex_status "$W" working
  export BOARD_CLOSE_WAIT=0
  close
  [ "$status" -eq 1 ]
  [ -d "$WT" ]
  [ ! -e "$BATS_TEST_TMPDIR/teardown-ran" ]
}

@test "close deletes a branch that only origin has, after a fetch" {
  start_worker
  git -C "$WT" commit -q --allow-empty -m work
  git -C "$WT" push -q origin HEAD:main
  # The push moved origin/main of the repo too: put it back, so only a fetch shows it.
  git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse main)"
  close
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
  ! git -C "$REPO" show-ref -q --verify refs/heads/fix-login
}

@test "close keeps a worktree with a detached HEAD that the default branch does not have" {
  start_worker
  git -C "$WT" checkout -q --detach
  git -C "$WT" commit -q --allow-empty -m loose
  close
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
  [[ "$stderr" == *"kept the worktree $WT: its detached HEAD has commits that the default branch does not have"* ]]
}

@test "close removes a worktree with a detached HEAD on the default branch" {
  start_worker
  git -C "$WT" checkout -q --detach
  close
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
}

@test "close keeps a worktree that another worker of the card uses" {
  start_worker
  first=$W
  start_worker
  [ "$W" != "$first" ]
  W=$first
  close
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  [ ! -e "$BATS_TEST_TMPDIR/teardown-ran" ]
}

@test "resume-clear removes the worktree of a done worker when the default branch has its work" {
  start_worker
  gone "$W"
  resume_clear
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
  ! git -C "$REPO" show-ref -q --verify refs/heads/fix-login
}

@test "resume-clear keeps the worktree of a done worker with work that is not merged, and runs its teardown" {
  start_worker
  git -C "$WT" commit -q --allow-empty -m work
  gone "$W"
  resume_clear
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  [ -z "$stderr" ]
  [ "$(cat "$BATS_TEST_TMPDIR/teardown-ran")" = "$WT with git" ]
}

@test "resume-clear keeps the worktree of a worker that is not done" {
  start_worker
  printf 'RESULT: WAITS FOR USER\n' >"$REPORT"
  gone "$W"
  resume_clear
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  [ ! -e "$BATS_TEST_TMPDIR/teardown-ran" ]
}
