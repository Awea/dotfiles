#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
# Tests for board-scan.sh. A fake vault and fake repos in the test folder.

setup() {
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  V="$OBSIDIAN_VAULT_PATH"
  mkdir -p "$HOME" "$V/Boards" "$V/Tasks" "$V/Projects"
}

# Write a board with cards in each column, the task notes, the project notes and repos.
make_board() {
  local repo_a="$BATS_TEST_TMPDIR/repo-a" repo_b="$BATS_TEST_TMPDIR/repo-b"
  mkdir -p "$repo_a/.claude" "$repo_b"
  printf '{"permissions":{"allow":["Bash(git push*)"]}}\n' >"$repo_a/.claude/settings.local.json"
  printf '{"permissions":{"allow":["Read","Bash(git status)"]}}\n' >"$repo_a/.claude/settings.readonly.json"
  printf -- '---\ntype: project\nrepo: %s\n---\n# A\n' "$repo_a" >"$V/Projects/alpha.md"
  mkdir -p "$HOME/code"
  ln -s "$repo_b" "$HOME/code/repo-b"
  printf -- '---\nrepo: "~/code/repo-b"\n---\n# B\n' >"$V/Projects/beta.md"
  printf -- '---\nmode: auto\n---\n## Prompt\n\n~~~\nRun.\n~~~\n' >"$V/Tasks/Tilde task.md"
  printf -- '---\ntype: task\nmode: auto\nrecurrence: 1d\n---\n# Check\n\n## Prompt\n\n```\nRun the check.\n```\n\n## Runs\n' >"$V/Tasks/Daily check.md"
  printf -- '---\ntype: task\n---\n# Other\n\n## Notes\n\n```\nnot a prompt\n```\n' >"$V/Tasks/Other task.md"
  cat >"$V/Boards/main.md" <<'EOF'
---
kanban-plugin: board
---

## 📥 Backlog

- [ ] 🟢 🔁 **[alpha] Daily check** @{2000-01-01}
	Last run ok. [[Tasks/Daily check|the check]] [[Projects/alpha]]
- [ ] 🟡 **[beta] Later work** @{2999-01-01}
	[[Tasks/Other task#Notes]] [[Projects/beta]]
- [ ] **No date and no link**

## 📋 This Week

- [ ] 🔴 **[beta] Someone else** owner: someone, more · waits for the user
	[[Tasks/Missing note]] [[Projects/beta]]

## 🔨 In Progress

- [ ] 🟡 **[alpha] Running**
	Started. [[Projects/alpha]]
- [ ] 🟠 **[beta] Two lines**
	First line, owner: someone
	Second line [[Tasks/Tilde task]] [[Projects/beta]]

## ⏳ Waiting On

- [x] 🟢 **[alpha] Checked waiting**
	Done but here.

## ✅ Done

- [x] 🟡 **[alpha] Finished** ✅ 2026-01-01
	Result.
- [x] 🟡 **[alpha] Older** ✅ 2025-01-01

## Odd column
- [ ] **Lost card**
EOF
}

# Write the board long.md with one card whose context line is longer than 200 characters
# and ends with the links of the card.
long_board() {
  local text
  text=$(printf 'x%.0s' $(seq 1 240))
  printf -- '---\nkanban-plugin: board\n---\n\n## ⏳ Waiting On\n\n- [ ] 🟡 **[alpha] Long card**\n\t%s [[Tasks/Daily check]] [[Projects/alpha]]\n- [ ] 🟢 **[alpha] Short card**\n\tShort. [[Projects/alpha]]\n' "$text" >"$V/Boards/long.md"
}

# Print output line $1 (from 0) of the last run.
line() { printf '%s\n' "${lines[$1]}"; }

@test "board-scan cards prints one line for each card of the open columns and a summary" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 8 ]
  [ "$(line 7 | jq -c '[.done, .board, .today, .other]')" = "$(jq -cn --arg t "$(date +%F)" '[2, "main", $t, 1]')" ]
  [[ "$stderr" == *"Odd column"* ]]
  [ "$(line 0 | jq -r .column)" = '📥 Backlog' ]
  [ "$(line 3 | jq -r .column)" = '📋 This Week' ]
  [ "$(line 4 | jq -r .column)" = '🔨 In Progress' ]
  [ "$(line 5 | jq -r .column)" = '🔨 In Progress' ]
  [ "$(line 6 | jq -r .column)" = '⏳ Waiting On' ]
}

@test "board-scan cards gives the exact title and context lines" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -r .line)" -eq 7 ]
  [ "$(line 0 | jq -r .title_line)" = "$(sed -n 7p "$V/Boards/main.md")" ]
  [ "$(line 0 | jq -r .context_line)" = "$(sed -n 8p "$V/Boards/main.md")" ]
  [ "$(line 0 | jq -r .context_line)" = $'\tLast run ok. [[Tasks/Daily check|the check]] [[Projects/alpha]]' ]
  [ "$(line 2 | jq -r .context_line)" = '' ]
  [ "$(line 2 | jq -r .line)" -eq 11 ]
}

@test "board-scan cards parses the title line fields" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -c '[.checked, .priority, .recurring, .date, .due, .title]')" = '[false,"🟢",true,"2000-01-01",true,"[alpha] Daily check"]' ]
  [ "$(line 1 | jq -c '[.priority, .recurring, .date, .due]')" = '["🟡",false,"2999-01-01",false]' ]
  [ "$(line 2 | jq -c '[.priority, .date, .due, .task, .project, .owner, .waits]')" = '[null,null,true,null,null,null,null]' ]
  [ "$(line 3 | jq -c '[.priority, .owner, .waits]')" = '["🔴","someone","the user"]' ]
  [ "$(line 6 | jq -c '.checked')" = true ]
  [ "$(line 5 | jq -c '[.priority, .owner]')" = '["🟠","someone"]' ]
}

@test "board-scan cards reads the task note and the project repo" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -c '[.task, .task_exists, .mode, .recurrence, .prompt]')" = '["Tasks/Daily check.md",true,"auto","1d",true]' ]
  [ "$(line 0 | jq -c '[.project, .repo, .policy, .readonly]')" = "$(jq -cn --arg r "$BATS_TEST_TMPDIR/repo-a" '["Projects/alpha.md",$r,"allow",2]')" ]
  [ "$(line 1 | jq -c '[.task, .task_exists, .mode, .recurrence, .prompt]')" = '["Tasks/Other task.md",true,null,null,false]' ]
  [ "$(line 1 | jq -c '[.repo, .policy, .readonly]')" = "$(jq -cn --arg r "$HOME/code/repo-b" '[$r,"missing",0]')" ]
  [ "$(line 3 | jq -c '[.task, .task_exists]')" = '["Tasks/Missing note.md",false]' ]
  [ "$(line 4 | jq -c '[.task, .project, .policy]')" = '[null,"Projects/alpha.md","allow"]' ]
}

@test "board-scan cards gives policy invalid for a settings file that is not JSON" {
  make_board
  printf '{bad\n' >"$BATS_TEST_TMPDIR/repo-a/.claude/settings.json"
  printf '{bad\n' >"$BATS_TEST_TMPDIR/repo-a/.claude/settings.readonly.json"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -c '[.policy, .readonly]')" = '["invalid",0]' ]
}

@test "board-scan cards exits 2 with no board, no vault or no kanban line" {
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards nothing
  [ "$status" -eq 2 ]
  [[ "$stderr" == *nothing* ]]
  printf '# Not a board\n\n## 📥 Backlog\n\n- [ ] **x**\n' >"$V/Boards/plain.md"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards plain
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  unset OBSIDIAN_VAULT_PATH
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards plain
  [ "$status" -eq 2 ]
}

@test "board-scan rules prints only the wanted sections of _CLAUDE.md" {
  cat >"$V/_CLAUDE.md" <<'EOF'
# Manual

## Section 0 - First rule
keep A
## Section 0.5 - Other
drop B
## Frontmatter Requirements
keep C
## Folder Map
drop D
## Do Not Touch
keep E
EOF
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" rules
  [ "$status" -eq 0 ]
  [ "$(grep -c keep <<<"$output")" -eq 3 ]
  [ "$(grep -c drop <<<"$output")" -eq 0 ]
  [ "$(grep -c 'Section 0.5' <<<"$output")" -eq 0 ]
  [ "$(grep -c '^# Manual' <<<"$output")" -eq 0 ]
  [ "${lines[0]}" = '## Section 0 - First rule' ]
}

@test "board-scan rules prints nothing when _CLAUDE.md is missing" {
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" rules
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the skill folder links board-scan.sh" {
  [ "$(readlink -f "$PLUGIN_DIR/../../../claude/skills/board-orchestrator/board-scan.sh")" = "$PLUGIN_DIR/board-scan.sh" ]
}

@test "board-scan cards keeps a context of more lines and reads its links" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 5 | jq -r .title_line)" = "$(sed -n 22p "$V/Boards/main.md")" ]
  [ "$(line 5 | jq -r .context_line)" = "$(sed -n 23,24p "$V/Boards/main.md")" ]
  [ "$(line 5 | jq -c '[.task, .mode, .prompt, .project]')" = '["Tasks/Tilde task.md","auto",true,"Projects/beta.md"]' ]
  [ "$(line 5 | jq -r .repo)" = "$HOME/code/repo-b" ]
}

@test "board-scan cards gives the board layout on the summary line" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 7 | jq -c '.blank_after')" = '{"📥 Backlog":true,"📋 This Week":true,"🔨 In Progress":true,"⏳ Waiting On":true,"✅ Done":true}' ]
  [ "$(line 7 | jq -r .done_top.title_line)" = "$(grep -F 'Finished' "$V/Boards/main.md")" ]
  [ "$(line 7 | jq -r .done_top.context_line)" = $'\tResult.' ]
  printf -- '---\nkanban-plugin: board\n---\n## 📥 Backlog\n- [ ] **a**\n## ✅ Done\n' >"$V/Boards/tight.md"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards tight
  [ "$status" -eq 0 ]
  [ "$(line 1 | jq -c '[.blank_after["📥 Backlog"], .blank_after["✅ Done"], .done_top, .other]')" = '[false,false,null,0]' ]
}

@test "board-scan cards gives readonly 0 for a read-only file with more JSON documents" {
  make_board
  printf '{"permissions":{"allow":["a"]}}\n{"permissions":{"allow":["b"]}}\n' >"$BATS_TEST_TMPDIR/repo-a/.claude/settings.readonly.json"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 8 ]
  [ "$(line 0 | jq -c '[.policy, .readonly]')" = '["allow",0]' ]
}

@test "board-scan cards gives policy allow for a repo set by dispatch policy-set allow" {
  make_board
  rm "$BATS_TEST_TMPDIR/repo-a/.claude/settings.local.json"
  git init -q "$BATS_TEST_TMPDIR/repo-a"
  git -C "$BATS_TEST_TMPDIR/repo-a" remote add origin git@github.com:o/r.git
  run bash "$PLUGIN_DIR/dispatch.sh" policy-set "$BATS_TEST_TMPDIR/repo-a" allow
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.deny | length' "$BATS_TEST_TMPDIR/repo-a/.claude/settings.local.json")" -eq 4 ]
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards main
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -r .policy)" = allow ]
}

@test "board-scan card prints only the cards whose title has the text, in any case" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" card main "[ALPHA] run"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(line 0 | jq -r .title)" = '[alpha] Running' ]
  [ "$(line 0 | jq -r .column)" = '🔨 In Progress' ]
  [ "$(line 0 | jq -r .context_line)" = $'\tStarted. [[Projects/alpha]]' ]
}

@test "board-scan card gives the same line as cards for that card" {
  make_board
  bash "$PLUGIN_DIR/board-scan.sh" cards main | jq -c 'select(.title == "[beta] Two lines")' >"$BATS_TEST_TMPDIR/all"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" card main "two lines"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cat "$BATS_TEST_TMPDIR/all")" ]
}

@test "board-scan card prints nothing when no title has the text" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" card main "no such card"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(line 0 | jq -r .board)" = main ]
}

@test "board-scan card with no text gives the usage" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" card main
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"card BOARD TEXT"* ]]
}

@test "board-scan card ends with the same summary line as cards, after a user edit" {
  make_board
  # The user removes the blank line after the Done heading in Obsidian.
  awk '!(p && /^$/) { print } { p = ($0 == "## ✅ Done") }' "$V/Boards/main.md" >"$BATS_TEST_TMPDIR/b"
  mv "$BATS_TEST_TMPDIR/b" "$V/Boards/main.md"
  bash "$PLUGIN_DIR/board-scan.sh" cards main | tail -1 >"$BATS_TEST_TMPDIR/all"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" card main "running"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(cat "$BATS_TEST_TMPDIR/all")" ]
  [ "$(line 1 | jq -r '.blank_after["✅ Done"]')" = false ]
  [ "$(line 1 | jq -r .done_top.title_line)" = '- [x] 🟡 **[alpha] Finished** ✅ 2026-01-01' ]
}

@test "the full scan gives only the first 200 characters of a long card, and marks it" {
  make_board
  long_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards long
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq '.context_line | length')" -eq 200 ]
  [ "$(line 0 | jq -r .context_line)" = "$(sed -n 8p "$V/Boards/long.md" | cut -c1-200)" ]
  [ "$(line 0 | jq .context_long)" = true ]
  [ "$(line 1 | jq .context_long)" = false ]
}

@test "the full scan still reads the links at the end of a long card" {
  make_board
  long_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards long
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -r .task)" = 'Tasks/Daily check.md' ]
  [ "$(line 0 | jq .task_exists)" = true ]
  [ "$(line 0 | jq -r .project)" = 'Projects/alpha.md' ]
}

@test "a context line of 200 characters after its tab is not long" {
  make_board
  printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n\n- [ ] 🟡 **[alpha] Full card**\n\t%s\n' "$(printf 'y%.0s' $(seq 1 200))" >"$V/Boards/long.md"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" cards long
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq .context_long)" = false ]
  [ "$(line 0 | jq -r .context_line)" = "$(sed -n 8p "$V/Boards/long.md")" ]
}

@test "the scan of one card gives the full text of a long card, to use as the old text of an edit" {
  make_board
  long_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" card long "long card"
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq -r .context_line)" = "$(sed -n 8p "$V/Boards/long.md")" ]
  [ "$(line 0 | jq .context_long)" = true ]
}

@test "board-scan prompt prints only the prompt block of a task note, not its runs" {
  make_board
  printf '### 2026-01-01\n\nOld run report.\n' >>"$V/Tasks/Daily check.md"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" prompt "Tasks/Daily check.md"
  [ "$status" -eq 0 ]
  [ "$output" = 'Run the check.' ]
}

@test "board-scan prompt reads a tilde fence" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" prompt "Tasks/Tilde task.md"
  [ "$status" -eq 0 ]
  [ "$output" = 'Run.' ]
}

@test "board-scan prompt exits 1 for a task note with no prompt block" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" prompt "Tasks/Other task.md"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"no prompt block"* ]]
}

@test "board-scan prompt exits 2 for a missing task note" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" prompt "Tasks/Missing note.md"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no task note"* ]]
}

# Write 2 phone messages to the inbox of the vault, and a second board with its own project.
make_inbox() {
  mkdir -p "$V/_inbox"
  printf 'check the PR 1219 against the backend\n' >"$V/_inbox/2026-11-04-173424.md"
  printf 'buy milk\nand eggs\n' >"$V/_inbox/2026-11-05-081500.md"
  cat >"$V/Boards/other.md" <<'BOARD'
---
kanban-plugin: board
---

## 📥 Backlog

- [ ] 🟢 **[gamma] Work** [[Projects/gamma]]
- [ ] 🟢 **[gamma] More work**
	[[Projects/gamma|g]] [[Projects/delta#Notes]]
BOARD
  printf '# Not a board\n[[Projects/omega]]\n' >"$V/Boards/notes.md"
}

@test "each phone message in the inbox shows with its file and its text, oldest first" {
  make_board
  make_inbox
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" inbox
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(line 0 | jq -c '[.file, .text, .truncated]')" = '["_inbox/2026-11-04-173424.md","check the PR 1219 against the backend\n",false]' ]
  [ "$(line 1 | jq -r .file)" = '_inbox/2026-11-05-081500.md' ]
  [ "$(line 1 | jq -r .text)" = $'buy milk\nand eggs' ]
}

@test "the inbox summary gives the count and the projects of each board" {
  make_board
  make_inbox
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" inbox
  [ "$status" -eq 0 ]
  [ "$(line 2 | jq -c .)" = '{"inbox":2,"boards":{"main":["Projects/alpha","Projects/beta"],"other":["Projects/delta","Projects/gamma"]}}' ]
}

@test "a Syncthing temp file in the inbox is not a message" {
  make_board
  make_inbox
  printf 'half written\n' >"$V/_inbox/.syncthing.2026-11-05-090000.md.tmp"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" inbox
  [ "$status" -eq 0 ]
  [ "$(line 2 | jq .inbox)" -eq 2 ]
  [[ "$output" != *'half written'* ]]
}

@test "a long phone message is cut at 2000 characters" {
  make_board
  mkdir -p "$V/_inbox"
  head -c 2500 /dev/zero | tr '\0' 'a' >"$V/_inbox/2026-11-05-100000.md"
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" inbox
  [ "$status" -eq 0 ]
  [ "$(line 0 | jq '.text | length')" -eq 2000 ]
  [ "$(line 0 | jq .truncated)" = true ]
}

@test "a vault with no inbox folder gives only the summary" {
  make_board
  run --separate-stderr bash "$PLUGIN_DIR/board-scan.sh" inbox
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(line 0 | jq .inbox)" -eq 0 ]
}
