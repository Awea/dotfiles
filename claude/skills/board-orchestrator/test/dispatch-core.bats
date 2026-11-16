#!/usr/bin/env bats
# The board commands that need no Herdr. Copied from herdr/plugins/agent-tabs/test/agent-tabs.bats.

bats_require_minimum_version 1.5.0
load helper

# Give the folder $1 a push policy in .claude/settings.local.json.
allow_push() {
  mkdir -p "$1/.claude"
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$1/.claude/settings.local.json"
}

# Run the next bash scripts as on macOS: with the BSD date, stat, chmod and tail, and
# with no setsid and no tac. lib.sh puts /usr/bin first in PATH, so a PATH without a
# command does not work: exported functions take the place of the commands. On macOS,
# use the real commands.
as_macos() {
  [ "$(uname -s)" != Darwin ] || return 0
  setsid() {
    printf 'setsid: command not found\n' >&2
    return 127
  }
  tac() {
    printf 'tac: command not found\n' >&2
    return 127
  }
  command() {
    if [ "$1" = -v ] && { [ "$2" = setsid ] || [ "$2" = tac ]; }; then
      return 1
    fi
    builtin command "$@"
  }
  # BSD date: no long options, -r takes seconds, and %N is a plain N.
  date() {
    local a args=()
    for a in "$@"; do
      case "$a" in
        --*)
          printf 'date: illegal option -- -\n' >&2
          return 1
          ;;
      esac
      args+=("${a//%N/N}")
    done
    if [ "${1:-}" = -r ] && [[ "${2:-}" == *[!0-9]* ]]; then
      printf 'date: illegal time format\n' >&2
      return 1
    fi
    builtin command date "${args[@]}"
  }
  # BSD stat: -f FORMAT, with %m (mtime), %Fm (mtime with a fraction), %Lp (mode).
  stat() {
    if [ "${1:-}" != -f ]; then
      printf 'stat: illegal option -- %s\n' "${1#-}" >&2
      return 1
    fi
    case "$2" in
      %m) builtin command stat -c %Y "$3" ;;
      %Fm) builtin command stat -c %.9Y "$3" ;;
      %Lp) builtin command stat -c %a "$3" ;;
      *) return 1 ;;
    esac
  }
  chmod() {
    if [[ "${1:-}" == --* ]]; then
      printf 'chmod: illegal option -- -\n' >&2
      return 1
    fi
    builtin command chmod "$@"
  }
  # BSD tail has -r: the lines in reverse order.
  tail() {
    if [ "${1:-}" = -r ]; then
      shift
      builtin command tac "$@"
    else
      builtin command tail "$@"
    fi
  }
  export -f setsid tac command date stat chmod tail
}

# Print the mode of the file $1, as 644. GNU stat takes -c, the macOS stat takes -f.
file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

# Make the folder $1 a git repo with the origin remote $2 (github.com by default). No
# network.
forge_remote() {
  git init -q "$1"
  git -C "$1" remote add origin "${2:-git@github.com:o/r.git}"
}

# Make the temp vault of an inbox-clear test, with one phone message and one task note.
inbox_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/_inbox" "$OBSIDIAN_VAULT_PATH/Tasks"
  MESSAGE="$OBSIDIAN_VAULT_PATH/_inbox/2026-11-04-173424.md"
  printf 'check the PR 1219\n' >"$MESSAGE"
  printf 'a task\n' >"$OBSIDIAN_VAULT_PATH/Tasks/X.md"
}

# Write the text $1 of a log line to a new file and print its path.
log_file() {
  local f
  f=$(mktemp "$BATS_TEST_TMPDIR/log.XXXXXX")
  printf '%s\n' "$1" >"$f"
  printf '%s\n' "$f"
}

# Make the temp vault of a log test, with the folders of a real vault.
log_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Dev Logs" "$OBSIDIAN_VAULT_PATH/Daily"
  LOG_NOTE="$OBSIDIAN_VAULT_PATH/Dev Logs/$(date +%F) - work (board orchestrator).md"
  DAILY="$OBSIDIAN_VAULT_PATH/Daily/$(date +%F).md"
}

# Make the temp vault of a note-add test: a board with a long card at line 7 that links
# Tasks/Check.md, a card at line 9 that links another note, and a card with no context.
note_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Tasks" "$OBSIDIAN_VAULT_PATH/Boards"
  TASK="$OBSIDIAN_VAULT_PATH/Tasks/Check.md"
  BOARD="$OBSIDIAN_VAULT_PATH/Boards/main.md"
  TODAY=$(date +%F)
  printf -- '---\nkanban-plugin: board\n---\n\n## ⏳ Waiting On\n\n- [ ] 🟡 **[alpha] Check**\n\tPR 12 pushed, head `abc`. [[Tasks/Check]] [[Projects/alpha]]\n- [ ] 🟢 **[alpha] Other**\n\tOther text. [[Tasks/Other]]\n- [ ] 🟢 **[alpha] Bare**\n' >"$BOARD"
}

# Make the temp vault of a run-add test, with a task note and a report.
run_vault() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Tasks"
  TASK="$OBSIDIAN_VAULT_PATH/Tasks/Check.md"
  REPORT="$BATS_TEST_TMPDIR/report.md"
  printf -- 'STATUS: OK\n\n# Checks\n\n| a | b |\n\n## Notes\n\n- all good\n' >"$REPORT"
  TODAY=$(date +%F)
}

@test "dispatch policy is missing when the folder has no settings" {
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = missing ]
}

@test "dispatch policy is allow with a push rule in settings.local.json allow" {
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
}

@test "dispatch policy is ask with a push rule in settings.json ask" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"ask":["Bash(git push origin*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
}

@test "dispatch policy ask wins over allow" {
  allow_push "$BATS_TEST_TMPDIR"
  printf '{"permissions":{"ask":["Bash(git push*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
}

@test "dispatch policy exits 2 for invalid JSON" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"settings.json"* ]]
}

@test "dispatch policy exits 2 when CWD is not a folder" {
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
}

@test "dispatch policy-set allow writes the 11 push rules" {
  forge_remote "$BATS_TEST_TMPDIR"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  run jq -r '.permissions.allow[]' "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  [ "${#lines[@]}" -eq 11 ]
  [ "${lines[0]}" = 'Bash(git push*)' ]
  grep -qF 'Bash(gh pr ready*)' "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  [ "$(jq '.permissions.allow | index("Bash(gh pr close*)") != null' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = true ]
  [ "$(jq -r '.permissions.allow[]' "$BATS_TEST_TMPDIR/.claude/settings.local.json" | grep -c 'merge')" -eq 0 ]
}

@test "dispatch policy-set allow and ask deny the 4 merge rules once and keep other deny entries" {
  forge_remote "$BATS_TEST_TMPDIR"
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json" kind
  for kind in allow ask; do
    rm -rf "$BATS_TEST_TMPDIR/.claude"
    mkdir -p "$BATS_TEST_TMPDIR/.claude"
    printf '{"permissions":{"deny":["Bash(rm -rf*)"]}}\n' >"$f"
    run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" "$kind"
    [ "$status" -eq 0 ]
    [ "$output" = "$kind" ]
    run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" "$kind"
    [ "$status" -eq 0 ]
    [ "$output" = "$kind" ]
    run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
    [ "$output" = "$kind" ]
    [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(rm -rf*)","Bash(gh pr merge*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
  done
}

@test "dispatch policy-set removes the old wide forge rules and keeps other rules" {
  forge_remote "$BATS_TEST_TMPDIR"
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Read","Bash(gh pr merge*)","Bash(gh release*)","Bash(gh api -X*)"],"ask":["Bash(gh pr review*)","Bash(make*)"]}}\n' >"$f"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$(jq -r '.permissions.allow[0]' "$f")" = Read ]
  [ "$(jq '.permissions.allow | length' "$f")" -eq 12 ]
  [ "$(jq -c '.permissions.ask' "$f")" = '["Bash(make*)"]' ]
  [ "$(jq -r '.permissions.allow[], .permissions.ask[]' "$f" | grep -cE 'merge|release|api -X|review')" -eq 0 ]
}

@test "dispatch policy-set keeps other keys and entries and adds no duplicate" {
  forge_remote "$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"env":{"A":"1"},"permissions":{"allow":["Read","Bash(git push*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$(jq -r .env.A "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 1 ]
  [ "$(jq -r '.permissions.allow[0]' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = Read ]
  [ "$(jq '.permissions.allow | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 12 ]
}

@test "dispatch policy-set ask writes under ask" {
  forge_remote "$BATS_TEST_TMPDIR"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  [ "$(jq '.permissions.ask | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 11 ]
  [ "$(jq '.permissions.allow // [] | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 0 ]
}

@test "dispatch policy-set allow after ask moves the push rules to allow, and ask after allow moves them back" {
  forge_remote "$BATS_TEST_TMPDIR"
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Read"],"ask":["Bash(make*)"],"deny":["Bash(rm -rf*)"]}}\n' >"$f"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$output" = ask ]
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq -c '.permissions.ask' "$f")" = '["Bash(make*)"]' ]
  [ "$(jq '.permissions.allow | length' "$f")" -eq 12 ]
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  [ "$(jq -c '.permissions.allow' "$f")" = '["Read"]' ]
  [ "$(jq '.permissions.ask | length' "$f")" -eq 12 ]
  [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(rm -rf*)","Bash(gh pr merge*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
}

@test "dispatch policy-set allow on a Forgejo remote writes the Forgejo rules and removes only the gh rules of policy-set" {
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  forge_remote "$BATS_TEST_TMPDIR" ssh://forgejo@git.example.org:2222/o/r.git
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Read","Bash(gh api repos/x/*)","Bash(gh pr create*)","Bash(gh pr merge*)"],"ask":["Bash(gh issue edit*)"],"deny":["Bash(gh repo delete*)","Bash(gh pr merge*)"]}}\n' >"$f"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq -c '.permissions.allow' "$f")" = '["Read","Bash(gh api repos/x/*)","Bash(git push*)","Bash(git -C * push*)","Bash(git -c * push*)","mcp__forgejo__create_pull_request","mcp__forgejo__update_pull_request","mcp__forgejo__create_issue","mcp__forgejo__update_issue","mcp__forgejo__create_issue_comment","mcp__forgejo__edit_issue_comment","mcp__forgejo__issue_state_change"]' ]
  [ "$(jq -c '.permissions.ask' "$f")" = '[]' ]
  [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(gh repo delete*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
  [ "$(grep -cE 'gh pr|gh issue' "$f")" -eq 0 ]
}

@test "dispatch policy-set with no remote writes the Forgejo rules" {
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"allow":["Bash(gh api repos/x/*)","Bash(gh pr create*)"],"deny":["Bash(gh repo delete*)"]}}\n' >"$f"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq '.permissions.allow | length' "$f")" -eq 11 ]
  [ "$(jq -r '.permissions.allow[0]' "$f")" = 'Bash(gh api repos/x/*)' ]
  [ "$(jq '.permissions.allow | index("mcp__forgejo__issue_state_change") != null' "$f")" = true ]
  [ "$(jq -c '.permissions.deny' "$f")" = '["Bash(gh repo delete*)","Bash(tea pr merge*)","Bash(tea pulls merge*)","mcp__forgejo__merge_pull_request"]' ]
  [ "$(grep -c 'gh pr' "$f")" -eq 0 ]
}

@test "dispatch policy-set gives GitHub for the https and scp forms of github.com" {
  local url f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  for url in https://github.com/o/r.git git@github.com:o/r.git; do
    rm -rf "$BATS_TEST_TMPDIR/.claude" "$BATS_TEST_TMPDIR/.git"
    forge_remote "$BATS_TEST_TMPDIR" "$url"
    run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
    [ "$status" -eq 0 ]
    [ "$(jq '.permissions.allow | index("Bash(gh pr create*)") != null' "$f")" = true ]
    [ "$(grep -c 'mcp__forgejo__create' "$f")" -eq 0 ]
  done
}

@test "dispatch policy-set ask on a Forgejo remote writes under ask and adds no duplicate" {
  local f="$BATS_TEST_TMPDIR/.claude/settings.local.json"
  forge_remote "$BATS_TEST_TMPDIR" ssh://forgejo@git.example.org:2222/o/r.git
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$output" = ask ]
  [ "$(jq '.permissions.ask | length' "$f")" -eq 10 ]
  [ "$(jq '.permissions.ask | index("mcp__forgejo__create_pull_request") != null' "$f")" = true ]
  [ "$(jq '.permissions.allow // [] | length' "$f")" -eq 0 ]
  [ "$(jq '.permissions.deny | length' "$f")" -eq 3 ]
}

@test "dispatch policy-set refuses a bad mode and invalid JSON" {
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" deny
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/.claude/settings.local.json" ]
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = '{bad' ]
}

@test "dispatch policy is missing with an empty or blank settings file" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  : >"$BATS_TEST_TMPDIR/.claude/settings.json"
  printf '  \n\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = missing ]
}

@test "dispatch policy-set allow on a blank settings.local.json writes the rules" {
  forge_remote "$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '  \n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$output" = allow ]
  [ "$(jq '.permissions.allow | length' "$BATS_TEST_TMPDIR/.claude/settings.local.json")" -eq 11 ]
}

@test "dispatch policy and policy-set refuse a file with two JSON documents" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{}\n{}\n' >"$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = $'{}\n{}' ]
}

@test "dispatch policy is deny with a push rule in deny, and deny wins" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '{"permissions":{"deny":["Bash(git push*)"],"ask":["Bash(git push*)"]}}\n' >"$BATS_TEST_TMPDIR/.claude/settings.json"
  allow_push "$BATS_TEST_TMPDIR"
  run bash "$SKILL_DIR/dispatch.sh" policy "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = deny ]
}

@test "dispatch policy-set keeps the file mode, and uses 644 for a new file" {
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  [ "$(file_mode "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 644 ]
  chmod 600 "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$(file_mode "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 600 ]
  [ "$(find "$BATS_TEST_TMPDIR/.claude" -name 'settings.local.json.*' | wc -l)" -eq 0 ]
}

@test "dispatch policy-set keeps the file mode on macOS" {
  as_macos
  run bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" allow
  [ "$status" -eq 0 ]
  chmod 600 "$BATS_TEST_TMPDIR/.claude/settings.local.json"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR" ask
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$BATS_TEST_TMPDIR/.claude/settings.local.json")" = 600 ]
}

@test "an orchestrator log line goes under Log of a new daily board note" {
  log_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'Fix the parser — done; PR #3')"
  [ "$status" -eq 0 ]
  [ -f "$LOG_NOTE" ]
  grep -qx "date: $(date +%F)" "$LOG_NOTE"
  grep -qx 'type: devlog' "$LOG_NOTE"
  grep -qx 'tags: \[devlog, board-orchestrator, work\]' "$LOG_NOTE"
  grep -qx 'ai-first: true' "$LOG_NOTE"
  grep -qx 'board: "\[\[Boards/work\]\]"' "$LOG_NOTE"
  grep -qx '## For future agent' "$LOG_NOTE"
  [ "$(tail -2 "$LOG_NOTE" | head -1)" = '## Log' ]
  tail -1 "$LOG_NOTE" | grep -qE '^- [0-9]{2}:[0-9]{2} Fix the parser — done; PR #3$'
}

@test "a second orchestrator log line goes after the first one" {
  log_vault
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'first card — done')"
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'second card — waits for the user')"
  [ "$(grep -c '^## Log$' "$LOG_NOTE")" -eq 1 ]
  tail -2 "$LOG_NOTE" | head -1 | grep -q 'first card — done$'
  tail -1 "$LOG_NOTE" | grep -q 'second card — waits for the user$'
}

@test "the orchestrator log adds its link at the end of the Work section of the daily note" {
  log_vault
  printf -- '---\ntype: daily\n---\n\n## Work\n\n- earlier work\n\n## Tasks\n\n- [ ] a task\n' >"$DAILY"
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  link="- [[Dev Logs/$(date +%F) - work (board orchestrator)]]"
  [ "$(grep -cxF -- "$link" "$DAILY")" -eq 1 ]
  [ "$(grep -nxF -- "$link" "$DAILY" | cut -d: -f1)" -eq 8 ]
  [ "$(sed -n 7p "$DAILY")" = '- earlier work' ]
  [ "$(sed -n 10p "$DAILY")" = '## Tasks' ]
  [ "$(tail -1 "$DAILY")" = '- [ ] a task' ]
}

@test "the orchestrator log adds its link to the daily note only once" {
  log_vault
  printf -- '## Work\n\n- earlier work\n' >"$DAILY"
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'another card — done')"
  [ "$(grep -c 'work (board orchestrator)' "$DAILY")" -eq 1 ]
}

@test "the orchestrator log appends its link to a daily note with no Work section" {
  log_vault
  printf -- '---\ntype: daily\n---\n\n## Tasks\n\n- [ ] a task\n' >"$DAILY"
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  [ "$(tail -1 "$DAILY")" = "- [[Dev Logs/$(date +%F) - work (board orchestrator)]]" ]
  grep -qx -- '- \[ \] a task' "$DAILY"
}

@test "the orchestrator log creates no daily note" {
  log_vault
  bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  [ ! -e "$DAILY" ]
}

@test "the orchestrator log with no text gives the usage" {
  log_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" log work
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh log BOARD FILE"* ]]
}

@test "the orchestrator log with no vault path fails" {
  unset OBSIDIAN_VAULT_PATH
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" log work "$(log_file 'a card — done')"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no vault path"* ]]
}

@test "a card title with a backtick and a dollar sign goes into the log as it is" {
  log_vault
  f=$(log_file 'Fix `date` and $HOME — done')
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" log work "$f"
  [ "$status" -eq 0 ]
  [[ "$(tail -1 "$LOG_NOTE")" == *' Fix `date` and $HOME — done' ]]
}

@test "a log text on two lines stays one log line" {
  log_vault
  f=$(log_file $'first part\nsecond part')
  bash "$SKILL_DIR/dispatch.sh" log work "$f"
  tail -1 "$LOG_NOTE" | grep -qE '^- [0-9]{2}:[0-9]{2} first part second part$'
}

@test "the orchestrator log with a missing text file fails and writes nothing" {
  log_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" log work "$BATS_TEST_TMPDIR/none"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"missing or empty"* ]]
  [ ! -e "$LOG_NOTE" ]
}

@test "a report summary gives the first line, the Result and Vault changes sections and the refused calls" {
  r="$BATS_TEST_TMPDIR/report.md"
  printf '%s\n' 'STATUS: REFUSED' '# Check fees' '' '## Result' 'Fees are ok.' 'REFUSED: git fetch' '' \
    '## Details' 'long detail' 'REFUSED: gh pr list' '' '## Vault changes' '- Boards/work.md: old -> new' >"$r"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" report "$r"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'STATUS: REFUSED' ]
  [[ "$output" == *$'## Result\nFees are ok.'* ]]
  [[ "$output" == *$'## Vault changes\n- Boards/work.md: old -> new'* ]]
  [[ "$output" == *'REFUSED: gh pr list'* ]]
  [[ "$output" != *'long detail'* ]]
  [ "${lines[-1]}" = "full report: $r (13 lines)" ]
}

@test "a report with no Result section gives its first 40 lines" {
  r="$BATS_TEST_TMPDIR/report.md"
  { printf 'RESULT: DONE\n'; for i in $(seq 2 50); do printf 'line %s\n' "$i"; done; } >"$r"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" report "$r"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 41 ]
  [ "${lines[39]}" = 'line 40' ]
  [ "${lines[40]}" = "full report: $r (50 lines)" ]
}

@test "a long Result section of a report is cut at 60 lines with a note" {
  r="$BATS_TEST_TMPDIR/report.md"
  { printf 'RESULT: DONE\n## Result\n'; for i in $(seq 1 80); do printf 'result %s\n' "$i"; done; } >"$r"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" report "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'result 59\n'* ]]
  [[ "$output" != *'result 60'* ]]
  [[ "$output" == *'section cut: 21 more lines'* ]]
}

@test "a report summary with no report file fails" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" report "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh report PATH"* ]]
}

@test "the first run of a recurring card adds a Runs section at the end of the task note" {
  run_vault
  printf -- '---\ntype: task\n---\n\n## Prompt\n\ndo it\n' >"$TASK"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$status" -eq 0 ]
  [ "$output" = "run-add: Tasks/Check.md $TODAY" ]
  expected=$(printf -- '---\ntype: task\n---\n\n## Prompt\n\ndo it\n\n## Runs\n\n### %s\n\nSTATUS: OK\n\n#### Checks\n\n| a | b |\n\n##### Notes\n\n- all good' "$TODAY")
  [ "$(cat "$TASK")" = "$expected" ]
}

@test "a run goes at the end of a Runs section that is the last section" {
  run_vault
  printf -- '## Prompt\n\ndo it\n\n## Runs\n\n### 2026-01-01\n\nSTATUS: OK\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(sed -n 9p "$TASK")" = 'STATUS: OK' ]
  [ "$(sed -n 10,11p "$TASK")" = "$(printf -- '\n### %s' "$TODAY")" ]
  [ "$(tail -1 "$TASK")" = '- all good' ]
  [ "$(grep -c '^## Runs$' "$TASK")" -eq 1 ]
}

@test "a run goes after the last run when a section follows Runs" {
  run_vault
  printf -- '## Runs\n\n### 2026-01-01\n\nold run\n\n## Links\n\n- a link\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -n "^### $TODAY\$" "$TASK" | cut -d: -f1)" -eq 7 ]
  [ "$(sed -n 5,6p "$TASK")" = "$(printf 'old run\n')" ]
  [ "$(grep -B2 '^## Links$' "$TASK" | head -1)" = '- all good' ]
  [ "$(tail -1 "$TASK")" = '- a link' ]
}

@test "a second record of the same card on the same day replaces the run of that day" {
  run_vault
  printf -- '## Runs\n\n### 2026-01-01\n\nold run\n\n### %s\n\nSTATUS: STOP\n\n#### First\n\n## Links\n\n- a link\n' "$TODAY" >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -c "^### $TODAY\$" "$TASK")" -eq 1 ]
  [ "$(grep -c 'STATUS: STOP' "$TASK")" -eq 0 ]
  [ "$(grep -c 'First' "$TASK")" -eq 0 ]
  grep -qx 'old run' "$TASK"
  grep -qx '#### Checks' "$TASK"
  [ "$(tail -1 "$TASK")" = '- a link' ]
}

@test "a run keeps a heading inside a code block of the report" {
  run_vault
  printf -- 'RESULT: DONE\n\n```\n# a shell comment\n```\n' >"$REPORT"
  printf -- '## Prompt\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  grep -qx 'RESULT: DONE' "$TASK"
  grep -qx '# a shell comment' "$TASK"
}

@test "a run after a fenced line that starts with ## goes after the fence, at the end of Runs" {
  run_vault
  printf -- '## Runs\n\n### 2026-01-01\n\n```\n## a quoted note\n### a quoted run\n```\n\nold end\n\n## Links\n\n- a link\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -n "^### $TODAY\$" "$TASK" | cut -d: -f1)" -eq 12 ]
  [ "$(sed -n 10p "$TASK")" = 'old end' ]
  grep -qx '## a quoted note' "$TASK"
  grep -qx '### a quoted run' "$TASK"
  [ "$(tail -1 "$TASK")" = '- a link' ]
}

@test "a second record on the same day replaces the whole run of that day, past a fenced ### line" {
  run_vault
  printf -- '## Runs\n\n### %s\n\n~~~\n### quoted\n~~~\n\nold tail\n\n## Links\n' "$TODAY" >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(grep -c -e quoted -e 'old tail' "$TASK")" -eq 0 ]
  [ "$(grep -c "^### $TODAY\$" "$TASK")" -eq 1 ]
  [ "$(tail -1 "$TASK")" = '## Links' ]
}

@test "a run sets the updated field of the task note to today" {
  run_vault
  printf -- '---\ntype: task\nupdated: 2026-01-01\n---\n\n## Prompt\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$(sed -n 1,4p "$TASK")" = "$(printf -- '---\ntype: task\nupdated: %s\n---' "$TODAY")" ]
}

@test "a run with no report gives the usage" {
  run_vault
  printf -- '## Prompt\n' >"$TASK"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh run-add NOTE REPORT"* ]]
}

@test "a run for a task note that is not in the vault fails" {
  run_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" run-add Tasks/None.md "$REPORT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no task note"* ]]
}

@test "a run with no vault path fails" {
  run_vault
  unset OBSIDIAN_VAULT_PATH
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" run-add Tasks/Check.md "$REPORT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no vault path"* ]]
}

@test "the long text of a card goes to the end of the Notes section of its task note" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Notes\n\n- old note\n\n## Runs\n\n### 2026-01-01\n' >"$TASK"
  cp "$BOARD" "$BATS_TEST_TMPDIR/board-before"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 0 ]
  [ "$output" = "note-add: Tasks/Check.md $TODAY" ]
  expected=$(printf -- '## Notes\n\n- old note\n\n### %s, from the board\n\nPR 12 pushed, head `abc`. [[Tasks/Check]] [[Projects/alpha]]\n\n## Runs\n\n### 2026-01-01' "$TODAY")
  [ "$(sed -n '5,$p' "$TASK")" = "$expected" ]
  cmp "$BOARD" "$BATS_TEST_TMPDIR/board-before"
}

@test "a task note with no Notes section gets one at its end" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Prompt\n\ndo it\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  expected=$(printf -- '## Prompt\n\ndo it\n\n## Notes\n\n### %s, from the board\n\nPR 12 pushed, head `abc`. [[Tasks/Check]] [[Projects/alpha]]' "$TODAY")
  [ "$(sed -n '5,$p' "$TASK")" = "$expected" ]
}

@test "a card text of more lines keeps its lines, with no tab at the start" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\tFirst line.\n\t\tSecond line. [[Tasks/Check]]\n' >"$BOARD"
  bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(tail -2 "$TASK")" = "$(printf 'First line.\n\tSecond line. [[Tasks/Check]]')" ]
}

@test "a Notes heading in a code block of an old run is not the Notes section" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Runs\n\n~~~\n## Notes\n~~~\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(grep -c '^## Notes$' "$TASK")" -eq 2 ]
  [ "$(sed -n 10,12p "$TASK")" = "$(printf -- '\n## Notes\n')" ]
}

@test "a card text with a backslash goes to the task note as it is" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\tThe path C:\\new\\tmp. [[Tasks/Check]]\n' >"$BOARD"
  bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(tail -1 "$TASK")" = 'The path C:\new\tmp. [[Tasks/Check]]' ]
}

@test "the copy of a card text sets the updated field of the task note to today" {
  note_vault
  printf -- '---\ntype: task\nupdated: 2026-01-01\n---\n' >"$TASK"
  bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$(sed -n 3p "$TASK")" = "updated: $TODAY" ]
}

@test "a line number that moved to a context line after a user edit changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 8 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no card [alpha] Check at line 8"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a card that links its task note and a related task note gives its text to its own note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\tSee [[Tasks/Other]] first. [[Tasks/Check]]\n' >"$BOARD"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$TASK")" = 'See [[Tasks/Other]] first. [[Tasks/Check]]' ]
}

@test "a card that links another task note changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 9 "[alpha] Other"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"links Tasks/Other"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a card with no context line changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 11 "[alpha] Bare"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no context line"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a copy to a task note that is not in the vault fails" {
  note_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no task note"* ]]
}

@test "a copy from a board that is not in the vault fails" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md other 7 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no board other"* ]]
}

@test "a copy with no line number gives the usage" {
  note_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh note-add NOTE BOARD LINE TITLE"* ]]
}

@test "a copy with no title gives the usage" {
  note_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh note-add NOTE BOARD LINE TITLE"* ]]
}

@test "a card of the user that took the line of the card after an edit changes no note" {
  note_vault
  printf -- '---\ntype: task\n---\n' >"$TASK"
  cp "$TASK" "$BATS_TEST_TMPDIR/task-before"
  # The user added a card at the top: the card Check moved from line 7 to line 9.
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟢 **[beta] User card**\n\tPrivate text. [[Projects/beta]]\n- [ ] 🟡 **[alpha] Check**\n\tLong text. [[Tasks/Check]]\n' >"$BOARD"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no card [alpha] Check at line 7"* ]]
  cmp "$TASK" "$BATS_TEST_TMPDIR/task-before"
}

@test "a heading in a card text goes under the entry of the day, not beside it" {
  note_vault
  printf -- '---\ntype: task\n---\n\n## Notes\n\n- old\n\n## Runs\n' >"$TASK"
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Check**\n\t## Plan [[Tasks/Check]]\n' >"$BOARD"
  bash "$SKILL_DIR/dispatch.sh" note-add Tasks/Check.md main 7 "[alpha] Check"
  grep -qx '##### Plan \[\[Tasks/Check\]\]' "$TASK"
  [ "$(grep -c '^## ' "$TASK")" -eq 2 ]
}

@test "a phone message that became a card leaves the inbox" {
  inbox_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" inbox-clear _inbox/2026-11-04-173424.md
  [ "$status" -eq 0 ]
  [ "$output" = 'inbox-clear: _inbox/2026-11-04-173424.md' ]
  [ ! -e "$MESSAGE" ]
}

@test "a phone message that the orchestrator of another board already cleared is gone" {
  inbox_vault
  rm "$MESSAGE"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" inbox-clear _inbox/2026-11-04-173424.md
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is gone"* ]]
}

@test "inbox-clear keeps a note outside the inbox" {
  inbox_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" inbox-clear Tasks/X.md
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh inbox-clear _inbox/NAME.md"* ]]
  [ -f "$OBSIDIAN_VAULT_PATH/Tasks/X.md" ]
}

@test "inbox-clear keeps a note that a path climbs out of the inbox to" {
  inbox_vault
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" inbox-clear _inbox/../Tasks/X.md
  [ "$status" -eq 2 ]
  [ -f "$OBSIDIAN_VAULT_PATH/Tasks/X.md" ]
}

@test "inbox-clear keeps a file in the inbox that is not a message" {
  inbox_vault
  printf 'half written\n' >"$OBSIDIAN_VAULT_PATH/_inbox/.syncthing.x.md.tmp"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" inbox-clear _inbox/.syncthing.x.md.tmp
  [ "$status" -eq 2 ]
  [ -f "$OBSIDIAN_VAULT_PATH/_inbox/.syncthing.x.md.tmp" ]
}
