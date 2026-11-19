#!/usr/bin/env bats
# hooks/guard.sh (PreToolUse Bash) and hooks/compact.sh (SessionStart compact).

bats_require_minimum_version 1.5.0
load helper

# guard COMMAND [CWD [SESSION]]: run the hook on a Bash call.
guard() {
  local json
  json=$(jq -cn --arg c "$1" --arg d "${2:-${REPO:-$BATS_TEST_TMPDIR}}" --arg s "${3:-s1}" --arg t "${TRANSCRIPT:-}" \
    '{session_id: $s, cwd: $d, tool_name: "Bash", tool_input: {command: $c}}
      + (if $t == "" then {} else {transcript_path: $t} end)')
  run bash "$SKILL_DIR/hooks/guard.sh" <<<"$json"
}

# decision: the permission decision of the last guard run, or empty.
decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$output"; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$output"; }

# branch_repo: REPO, a clone of a bare origin with the branch master, with the branch
# push policy, on a new branch feat that origin does not have.
branch_repo() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  ORIGIN="$BATS_TEST_TMPDIR/origin.git" REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/master
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b master
  git -C "$REPO" commit -q --allow-empty -m one
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin master
  git -C "$REPO" remote set-head origin master
  mkdir -p "$REPO/.claude"
  printf '{"env":{"BOARD_PUSH_POLICY":"branch"}}\n' >"$REPO/.claude/settings.local.json"
  git -C "$REPO" checkout -q -b feat
  git -C "$REPO" commit -q --allow-empty -m two
}

# push_feat: the first push of feat, after the user allowed it.
push_feat() {
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
  git -C "$REPO" push -q -u origin HEAD 2>/dev/null
  git -C "$REPO" commit -q --allow-empty -m three
}

# agent_call EPOCH TYPE: add to TRANSCRIPT an Agent call of the subagent type TYPE at
# the time EPOCH, as Claude Code writes it.
agent_call() {
  jq -cn --argjson e "$1" --arg t "$2" \
    '{type: "assistant", timestamp: ($e | todate | sub("Z$"; ".123Z")),
      message: {content: [{type: "tool_use", name: "Agent",
        input: {subagent_type: $t, description: "Review the branch", prompt: "x"}}]}}' >>"$TRANSCRIPT"
}

# review_repo: branch_repo with an empty transcript.
review_repo() {
  branch_repo
  TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
  : >"$TRANSCRIPT"
}

compact() { run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'; }

@test "guard asks for the first push of a branch in a branch repo" {
  as_worker
  branch_repo
  guard 'git push -u origin HEAD'
  [ "$status" -eq 0 ]
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"first push of the branch feat"* ]]
}

@test "guard allows a later push to the branch after the user allowed its first push" {
  as_worker
  branch_repo
  push_feat
  for c in 'git push' 'git push origin feat' 'git push -u origin HEAD' 'git push --force-with-lease' \
    'git push origin HEAD:feat' 'git push -q origin refs/heads/feat' 'git push origin feat:' "cd $REPO && git push"; do
    guard "$c"
    [ "$status" -eq 0 ]
    [ "$(decision)" = allow ] || { echo "not allowed: $c: $output"; return 1; }
  done
  guard "git -C $REPO push" "$BATS_TEST_TMPDIR"
  [ "$(decision)" = allow ]
  guard 'git push' "$REPO/.claude"
  [ "$(decision)" = allow ]
}

@test "guard asks again when the user refused the first push" {
  as_worker
  branch_repo
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
}

@test "guard asks for the first push to a branch that origin already has" {
  as_worker
  branch_repo
  git -C "$REPO" push -q origin feat 2>/dev/null
  guard 'git push origin feat'
  [ "$(decision)" = ask ]
}

@test "guard keeps the approval of a branch to one session" {
  as_worker
  branch_repo
  push_feat
  guard 'git push' "$REPO" s2
  [ "$(decision)" = ask ]
}

@test "guard asks for each push to the default branch, also a bare push on it" {
  as_worker
  branch_repo
  push_feat
  for c in 'git push origin master' 'git push origin HEAD:master' 'git push origin feat:refs/heads/master' \
    'git push origin HEAD:main' 'git push origin feat master'; do
    guard "$c"
    [ "$(decision)" = ask ] || { echo "not asked: $c: $output"; return 1; }
    [[ "$(reason)" == *"default branch"* ]]
  done
  git -C "$REPO" checkout -q master
  git -C "$REPO" commit -q --allow-empty -m four
  guard 'git push'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch master"* ]]
  guard 'git push'
  [ "$(decision)" = ask ]
}

@test "guard asks for a bare push to a default branch upstream" {
  as_worker
  branch_repo
  git -C "$REPO" checkout -q -b other --track origin/master
  guard 'git push'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch"* ]]
}

@test "guard asks for a push that it cannot read" {
  as_worker
  branch_repo
  push_feat
  for c in 'git push && echo ok' 'git commit -m x; git push' 'git push 2>&1 | tail -3' 'git push -f' \
    'git push --force' 'git push origin +feat' 'git push --all' 'git push --tags' 'git push other feat' \
    'git push origin :feat' 'git push --delete origin feat' 'git push origin "feat"' 'git -c push.default=matching push' \
    'GIT_TRACE=1 git push' 'git push origin v1:refs/tags/v1' 'git push --mirror' 'git push origin $(git branch --show-current)'; do
    guard "$c"
    [ "$(decision)" = ask ] || { echo "not asked: $c: $output"; return 1; }
  done
}

@test "guard asks for a cd folder name with a command in it" {
  as_worker
  branch_repo
  push_feat
  mkdir "$REPO/\$(touch\${IFS}pwned)"
  guard "cd \$(touch\${IFS}pwned) && git push origin feat"
  [ "$(decision)" = ask ]
}

@test "guard asks for a short name or a source that reaches another ref" {
  as_worker
  branch_repo
  push_feat
  git -C "$REPO" tag v1
  git -C "$REPO" update-ref refs/remotes/origin/heads/master HEAD
  for c in 'git push origin HEAD:heads/master' 'git push origin heads/master' 'git push origin v1:feat' \
    'git push origin HEAD:tags/v1' 'git push origin HEAD:remotes/x' 'git push origin v1'; do
    guard "$c"
    [ "$(decision)" = ask ] || { echo "not asked: $c: $output"; return 1; }
  done
  git -C "$REPO" checkout -q master
  guard 'git push origin @'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch master"* ]]
}

@test "guard reads origin, not the local origin refs, for the approval" {
  as_worker
  branch_repo
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
  git -C "$REPO" update-ref refs/remotes/origin/feat HEAD
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
}

@test "guard asks for a push with a push setting that changes the target" {
  as_worker
  branch_repo
  push_feat
  local key
  for key in push.default=matching remote.origin.mirror=true remote.origin.pushurl=/x \
    url./y.pushInsteadOf=/z remote.origin.push=refs/heads/feat:refs/heads/master \
    push.recurseSubmodules=on-demand submodule.recurse=true; do
    git -C "$REPO" config "${key%%=*}" "${key#*=}"
    guard 'git push'
    [ "$(decision)" = ask ] || { echo "not asked: $key: $output"; return 1; }
    git -C "$REPO" config --unset "${key%%=*}"
  done
  guard 'git push'
  [ "$(decision)" = allow ]
}

@test "guard asks for a push to the default branch of origin when the local origin/HEAD is gone" {
  as_worker
  branch_repo
  git -C "$REPO" push -q origin master:trunk 2>/dev/null
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/trunk
  git -C "$REPO" remote set-head origin -d
  guard 'git push origin HEAD:trunk'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch trunk"* ]]
}

@test "guard reads the policy of a card folder in a sub-folder of the repo" {
  as_worker
  branch_repo
  mkdir -p "$REPO/app/.claude"
  mv "$REPO/.claude/settings.local.json" "$REPO/app/.claude/"
  guard 'git push origin HEAD:master' "$REPO/app"
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch"* ]]
}

# ssh_origin SCRIPT: origin as an ssh URL, with core.sshCommand set to SCRIPT, a fake ssh
# that runs the git command on this host.
ssh_origin() {
  printf '#!/bin/sh\n%s\nfor a; do last=$a; done\nexec sh -c "$last"\n' "$1" >"$BATS_TEST_TMPDIR/fake-ssh"
  chmod +x "$BATS_TEST_TMPDIR/fake-ssh"
  unset GIT_SSH_COMMAND
  git -C "$REPO" config core.sshCommand "$BATS_TEST_TMPDIR/fake-ssh"
  git -C "$REPO" remote set-url origin "ssh://fake$ORIGIN"
}

@test "guard reads origin with the core.sshCommand of the repo" {
  as_worker
  branch_repo
  ssh_origin ':'
  push_feat
  guard 'git push'
  [ "$(decision)" = allow ]
}

@test "guard asks when origin does not answer in 5 s" {
  as_worker
  branch_repo
  push_feat
  ssh_origin 'sleep 30'
  SECONDS=0
  guard 'git push'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"could not read origin in 5 s"* ]]
  [ "$SECONDS" -lt 9 ]
}

@test "guard asks for a PR body edit in a branch repo" {
  as_worker
  branch_repo
  guard 'gh pr edit 12 --body-file /tmp/b.md'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"PR body"* ]]
}

@test "guard does not decide a push in an ask or allow repo, or outside a repo" {
  as_worker
  branch_repo
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$REPO/.claude/settings.local.json"
  guard 'git push origin master'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  guard 'gh pr edit 1 --body x'
  [ -z "$output" ]
  guard 'git push' "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# allow_repo: the push policy allow in REPO: the branch rules do not decide.
allow_repo() { printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$REPO/.claude/settings.local.json"; }

@test "guard refuses a push when no reviewer started in the session" {
  as_worker
  review_repo
  allow_repo
  guard 'git push -u origin feat'
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"no reviewer agent started in this session"* ]]
  [[ "$(reason)" == *"subagent_type reviewer"* ]]
  agent_call 1800000100 general-purpose
  guard 'git push -u origin feat'
  [ "$(decision)" = deny ]
}

@test "guard allows a push when a reviewer started in the session, before or after the commits" {
  as_worker
  review_repo
  allow_repo
  agent_call 1700000000 reviewer
  guard 'git push -u origin feat'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  git -C "$REPO" commit -q --allow-empty -m four
  guard 'git push'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard allows a commit and its push in one call after a reviewer started" {
  as_worker
  review_repo
  allow_repo
  git -C "$REPO" push -q -u origin feat 2>/dev/null
  agent_call 1700000000 reviewer
  guard 'git commit --allow-empty -m x && git push'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard refuses a push with no review before the branch policy question" {
  as_worker
  review_repo
  guard 'git push -u origin HEAD'
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
  agent_call 1700000000 reviewer
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"first push of the branch feat"* ]]
  [[ "$(reason)" != *"reviewer"* ]]
}

@test "guard allows a branch delete with no reviewer" {
  as_worker
  review_repo
  allow_repo
  for c in 'git push origin --delete old' 'git push -d origin old' 'git push origin :old'; do
    guard "$c"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "guard refuses a push with no review when the cwd is outside the repo" {
  as_worker
  review_repo
  allow_repo
  guard "git -C $REPO commit --allow-empty -m \"a b\" && git -C $REPO push" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
}

@test "guard reads a reviewer call past a cut-off line of the transcript" {
  as_worker
  review_repo
  allow_repo
  agent_call 1700000000 reviewer
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"reviewer"' >>"$TRANSCRIPT"
  guard 'git push -u origin feat'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does not check the review with no transcript" {
  as_worker
  review_repo
  allow_repo
  unset TRANSCRIPT
  guard 'git push -u origin feat'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# The role is in the env of the pane.
as_worker() { export REX_BLOCK=b1 REX_SESSION=rs1 BOARD=garden BOARD_ROLE=worker BOARD_NAME=w1; }
as_rex_orchestrator() { export REX_BLOCK=b1 BOARD="${1:-garden}" BOARD_ROLE=orchestrator; }

@test "guard allows an agent start and a slow command in a Rex worker, outside rex (Rex)" {
  as_worker
  for c in 'claude "review the branch"' 'codex' 'make test' 'bin/wait-deploy 4fb7f80'; do
    guard "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c"; return 1; }
    [ -z "$output" ]
  done
}

@test "guard allows a command of a Rex orchestrator and of a Rex pane not on a board (Rex)" {
  as_rex_orchestrator
  guard 'claude "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  unset BOARD BOARD_ROLE
  guard 'claude "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
@test "guard allows a later push to the branch after the user allowed its first push (Rex)" {
  as_worker
  branch_repo
  push_feat
  for c in 'git push' 'git push origin feat' 'git push -u origin HEAD' 'git push --force-with-lease' \
    'git push origin HEAD:feat' 'git push -q origin refs/heads/feat' 'git push origin feat:' "cd $REPO && git push"; do
    guard "$c"
    [ "$status" -eq 0 ]
    [ "$(decision)" = allow ] || { echo "not allowed: $c: $output"; return 1; }
  done
  guard "git -C $REPO push" "$BATS_TEST_TMPDIR"
  [ "$(decision)" = allow ]
  guard 'git push' "$REPO/.claude"
  [ "$(decision)" = allow ]
}

@test "guard asks again when the user refused the first push (Rex)" {
  as_worker
  branch_repo
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
}

@test "guard asks for the first push to a branch that origin already has (Rex)" {
  as_worker
  branch_repo
  git -C "$REPO" push -q origin feat 2>/dev/null
  guard 'git push origin feat'
  [ "$(decision)" = ask ]
}

@test "guard keeps the approval of a branch to one session (Rex)" {
  as_worker
  branch_repo
  push_feat
  guard 'git push' "$REPO" s2
  [ "$(decision)" = ask ]
}

@test "guard asks for each push to the default branch, also a bare push on it (Rex)" {
  as_worker
  branch_repo
  push_feat
  for c in 'git push origin master' 'git push origin HEAD:master' 'git push origin feat:refs/heads/master' \
    'git push origin HEAD:main' 'git push origin feat master'; do
    guard "$c"
    [ "$(decision)" = ask ] || { echo "not asked: $c: $output"; return 1; }
    [[ "$(reason)" == *"default branch"* ]]
  done
  git -C "$REPO" checkout -q master
  git -C "$REPO" commit -q --allow-empty -m four
  guard 'git push'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch master"* ]]
  guard 'git push'
  [ "$(decision)" = ask ]
}

@test "guard asks for a bare push to a default branch upstream (Rex)" {
  as_worker
  branch_repo
  git -C "$REPO" checkout -q -b other --track origin/master
  guard 'git push'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch"* ]]
}

@test "guard asks for a push that it cannot read (Rex)" {
  as_worker
  branch_repo
  push_feat
  for c in 'git push && echo ok' 'git commit -m x; git push' 'git push 2>&1 | tail -3' 'git push -f' \
    'git push --force' 'git push origin +feat' 'git push --all' 'git push --tags' 'git push other feat' \
    'git push origin :feat' 'git push --delete origin feat' 'git push origin "feat"' 'git -c push.default=matching push' \
    'GIT_TRACE=1 git push' 'git push origin v1:refs/tags/v1' 'git push --mirror' 'git push origin $(git branch --show-current)'; do
    guard "$c"
    [ "$(decision)" = ask ] || { echo "not asked: $c: $output"; return 1; }
  done
}

@test "guard asks for a cd folder name with a command in it (Rex)" {
  as_worker
  branch_repo
  push_feat
  mkdir "$REPO/\$(touch\${IFS}pwned)"
  guard "cd \$(touch\${IFS}pwned) && git push origin feat"
  [ "$(decision)" = ask ]
}

@test "guard asks for a short name or a source that reaches another ref (Rex)" {
  as_worker
  branch_repo
  push_feat
  git -C "$REPO" tag v1
  git -C "$REPO" update-ref refs/remotes/origin/heads/master HEAD
  for c in 'git push origin HEAD:heads/master' 'git push origin heads/master' 'git push origin v1:feat' \
    'git push origin HEAD:tags/v1' 'git push origin HEAD:remotes/x' 'git push origin v1'; do
    guard "$c"
    [ "$(decision)" = ask ] || { echo "not asked: $c: $output"; return 1; }
  done
  git -C "$REPO" checkout -q master
  guard 'git push origin @'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch master"* ]]
}

@test "guard reads origin, not the local origin refs, for the approval (Rex)" {
  as_worker
  branch_repo
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
  git -C "$REPO" update-ref refs/remotes/origin/feat HEAD
  guard 'git push -u origin HEAD'
  [ "$(decision)" = ask ]
}

@test "guard asks for a push with a push setting that changes the target (Rex)" {
  as_worker
  branch_repo
  push_feat
  local key
  for key in push.default=matching remote.origin.mirror=true remote.origin.pushurl=/x \
    url./y.pushInsteadOf=/z remote.origin.push=refs/heads/feat:refs/heads/master \
    push.recurseSubmodules=on-demand submodule.recurse=true; do
    git -C "$REPO" config "${key%%=*}" "${key#*=}"
    guard 'git push'
    [ "$(decision)" = ask ] || { echo "not asked: $key: $output"; return 1; }
    git -C "$REPO" config --unset "${key%%=*}"
  done
  guard 'git push'
  [ "$(decision)" = allow ]
}

@test "guard asks for a push to the default branch of origin when the local origin/HEAD is gone (Rex)" {
  as_worker
  branch_repo
  git -C "$REPO" push -q origin master:trunk 2>/dev/null
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/trunk
  git -C "$REPO" remote set-head origin -d
  guard 'git push origin HEAD:trunk'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch trunk"* ]]
}

@test "guard reads the policy of a card folder in a sub-folder of the repo (Rex)" {
  as_worker
  branch_repo
  mkdir -p "$REPO/app/.claude"
  mv "$REPO/.claude/settings.local.json" "$REPO/app/.claude/"
  guard 'git push origin HEAD:master' "$REPO/app"
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"default branch"* ]]
}

# ssh_origin SCRIPT: origin as an ssh URL, with core.sshCommand set to SCRIPT, a fake ssh
# that runs the git command on this host.
ssh_origin() {
  printf '#!/bin/sh\n%s\nfor a; do last=$a; done\nexec sh -c "$last"\n' "$1" >"$BATS_TEST_TMPDIR/fake-ssh"
  chmod +x "$BATS_TEST_TMPDIR/fake-ssh"
  unset GIT_SSH_COMMAND
  git -C "$REPO" config core.sshCommand "$BATS_TEST_TMPDIR/fake-ssh"
  git -C "$REPO" remote set-url origin "ssh://fake$ORIGIN"
}

@test "guard reads origin with the core.sshCommand of the repo (Rex)" {
  as_worker
  branch_repo
  ssh_origin ':'
  push_feat
  guard 'git push'
  [ "$(decision)" = allow ]
}

@test "guard asks when origin does not answer in 5 s (Rex)" {
  as_worker
  branch_repo
  push_feat
  ssh_origin 'sleep 30'
  SECONDS=0
  guard 'git push'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"could not read origin in 5 s"* ]]
  [ "$SECONDS" -lt 9 ]
}

@test "guard asks for a PR body edit in a branch repo (Rex)" {
  as_worker
  branch_repo
  guard 'gh pr edit 12 --body-file /tmp/b.md'
  [ "$(decision)" = ask ]
  [[ "$(reason)" == *"PR body"* ]]
}

@test "guard does not decide a push in an ask or allow repo, or outside a repo (Rex)" {
  as_worker
  branch_repo
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$REPO/.claude/settings.local.json"
  guard 'git push origin master'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  guard 'gh pr edit 1 --body x'
  [ -z "$output" ]
  guard 'git push' "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does not decide a push outside a worker (Rex)" {
  branch_repo
  as_rex_orchestrator
  guard 'git push origin master'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
@test "compact speaks only for an orchestrator (Rex)" {
  as_rex_orchestrator
  compact
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = SessionStart ]
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$output")
  [[ "$ctx" == *"~/.claude/skills/board-orchestrator/SKILL.md"* ]]
  [[ "$ctx" == *"orchestrator of the board garden"* ]]
}

@test "compact gives the whole board name as the arguments (Rex)" {
  as_rex_orchestrator "my board"
  compact
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$output")
  [[ "$ctx" == *'with "my board" as the whole argument text'* ]]
}
