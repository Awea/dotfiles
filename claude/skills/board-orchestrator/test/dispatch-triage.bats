#!/usr/bin/env bats
# dispatch.sh triage-check, triage-apply and triage: the board triage.

bats_require_minimum_version 1.5.0
load helper

setup() {
  base_setup
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  V="$OBSIDIAN_VAULT_PATH"
  mkdir -p "$V/Boards" "$V/Projects" "$V/Tasks"
}

# big_board N [FRONTMATTER]: the board alpha with N open cards in the Backlog, one
# checked card in Waiting On and one Done card.
big_board() {
  local i
  {
    printf -- '---\nkanban-plugin: board\n%s---\n\n## 📥 Backlog\n\n' "${2:-}"
    for ((i = 1; i <= $1; i++)); do printf -- '- [ ] 🟢 **[alpha] Card %d**\n\tState %d.\n' "$i" "$i"; done
    printf '\n## ⏳ Waiting On\n\n- [x] 🟢 **[alpha] Checked**\n\n## ✅ Done\n\n- [x] 🟡 **[alpha] Old** ✅ 2026-01-01\n'
  } >"$V/Boards/alpha.md"
}

check() { run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage-check "${1:-alpha}"; }

# epoch_days_ago N: the epoch seconds of N days ago.
epoch_days_ago() { echo $(($(date +%s) - $1 * 86400)); }

@test "triage-check is due over the default limit of 100 open cards" {
  big_board 101
  check
  [ "$status" -eq 0 ]
  [ "$output" = "triage: due 101 open cards, limit 100" ]
}

@test "triage-check is not due at the limit, and a checked card is not open" {
  big_board 100
  check
  [ "$status" -eq 0 ]
  [ "$output" = "triage: not due, 100 open cards, limit 100" ]
}

@test "triage-limit in the board frontmatter replaces the limit of 100" {
  big_board 6 $'triage-limit: 5\n'
  check
  [ "$output" = "triage: due 6 open cards, limit 5" ]
}

@test "a triage-limit that is not a positive number gives the limit of 100" {
  big_board 6 $'triage-limit: many\n'
  check
  [ "$output" = "triage: not due, 6 open cards, limit 100" ]
}

@test "a due check starts a cool-down of 14 days" {
  big_board 6 $'triage-limit: 5\n'
  check
  [ "$output" = "triage: due 6 open cards, limit 5" ]
  check
  [ "$status" -eq 0 ]
  [ "$output" = "triage: not due, 6 open cards, limit 5, last $(date +%F)" ]
}

@test "triage-check is due again 14 days after the last offer" {
  big_board 6 $'triage-limit: 5\n'
  mkdir -p "$XDG_STATE_HOME/board-orchestrator-hc/triage"
  printf '%s 2026-01-01\n' "$(epoch_days_ago 13)" >"$XDG_STATE_HOME/board-orchestrator-hc/triage/alpha"
  check
  [ "$output" = "triage: not due, 6 open cards, limit 5, last 2026-01-01" ]
  printf '%s 2026-01-01\n' "$(epoch_days_ago 14)" >"$XDG_STATE_HOME/board-orchestrator-hc/triage/alpha"
  check
  [ "$output" = "triage: due 6 open cards, limit 5" ]
}

@test "triage-check of a board that is not in the vault exits 2" {
  check nothing
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no board nothing"* ]]
}

@test "triage-check with no board gives the usage" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage-check
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh triage-check BOARD"* ]]
}

# apply_board [DONE_TOP]: the board alpha for triage-apply. DONE_TOP is the top Done card.
apply_board() {
  cat >"$V/Boards/alpha.md" <<EOF
---
kanban-plugin: board
---

## 📥 Backlog

- [ ] 🟢 **[alpha] Ship it**
	PR merged. [[Projects/alpha]]
- [ ] 🟡 **[alpha] Old idea**
	Nobody works on it.
- [ ] 🟡 **[alpha] Twin**
	Same.
- [ ] 🟡 **[alpha] Two lines**
	Line one.
	Line two.

## 📋 This Week
- [ ] 🟡 **[alpha] Twin**
	Same.
- [ ] 🟠 **[alpha] Busy**
	Worker 01a1ef15 works.
- [ ] **[alpha] No context**

## ✅ Done

${1:-- [x] 🟡 **[alpha] Finished** ✅ 2026-01-01}
	Done before.
- [x] 🟢 **[alpha] Old idea**
	Nobody works on it.
EOF
  cp "$V/Boards/alpha.md" "$BATS_TEST_TMPDIR/before.md"
}

# report LINE...: a triage report with the LINEs in its jsonl block.
report() {
  {
    printf 'RESULT: DONE\n\n## Result\n\nA triage.\n\n## Vault changes\n\n```jsonl\n'
    printf '%s\n' "$@"
    printf '```\n\n- A note change.\n'
  } >"$BATS_TEST_TMPDIR/report.md"
}

# change OP TITLE_LINE CONTEXT_LINE [NEW]: one jsonl line.
change() {
  jq -cn --arg op "$1" --arg t "$2" --arg c "$3" --arg n "${4-}" \
    '{op: $op, title_line: $t, context_line: $c} + (if $ARGS.positional[0] == "new" then {new: $n} else {} end)' \
    --args ${4+new}
}

apply() { run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage-apply alpha "$BATS_TEST_TMPDIR/report.md"; }

# board_diff: the diff of the board against the board before the apply.
board_diff() { diff "$BATS_TEST_TMPDIR/before.md" "$V/Boards/alpha.md" || true; }

SHIP='- [ ] 🟢 **[alpha] Ship it**'
SHIP_CTX=$'\tPR merged. [[Projects/alpha]]'

@test "triage-apply context replaces the context lines of the card" {
  apply_board
  report "$(change context '- [ ] 🟡 **[alpha] Two lines**' $'\tLine one.\n\tLine two.' 'One line now.')"
  apply
  [ "$status" -eq 0 ]
  [ "$output" = "triage-apply: applied 1 of 1" ]
  [ "$(grep -A1 -F '**[alpha] Two lines**' "$V/Boards/alpha.md" | tail -1)" = $'\tOne line now.' ]
  ! grep -q 'Line two' "$V/Boards/alpha.md"
}

@test "triage-apply delete removes the title and context lines" {
  apply_board
  report "$(change delete '- [ ] 🟡 **[alpha] Two lines**' $'\tLine one.\n\tLine two.')"
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
  [ "$(board_diff | grep -c '^<')" -eq 3 ]
  [ "$(board_diff | grep -c '^>')" -eq 0 ]
}

@test "triage-apply done moves the card to the top of Done in the form of the top Done card" {
  apply_board
  report "$(change done "$SHIP" "$SHIP_CTX")"
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
  [ "$(grep -A2 -F '## ✅ Done' "$V/Boards/alpha.md" | tail -1)" = "- [x] 🟢 **[alpha] Ship it** ✅ $(date +%F)" ]
  [ "$(grep -A3 -F '## ✅ Done' "$V/Boards/alpha.md" | tail -1)" = "$SHIP_CTX" ]
  [ "$(grep -c -F 'Ship it' "$V/Boards/alpha.md")" -eq 1 ]
}

@test "triage-apply done copies a strikethrough title and a month-day date" {
  apply_board '- [x] ~~🟡 **[alpha] Finished**~~ ✅ Oct 2'
  report "$(change done "$SHIP" "$SHIP_CTX")"
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
  day=$(LC_ALL=C date +%d)
  [ "$(grep -A2 -F '## ✅ Done' "$V/Boards/alpha.md" | tail -1)" = "- [x] ~~🟢 **[alpha] Ship it**~~ ✅ $(LC_ALL=C date +%b) $((10#$day))" ]
}

@test "triage-apply done with new sets the context line" {
  apply_board
  report "$(change done "$SHIP" "$SHIP_CTX" 'Merged in PR 12.')"
  apply
  [ "$(grep -A3 -F '## ✅ Done' "$V/Boards/alpha.md" | tail -1)" = $'\tMerged in PR 12.' ]
}

@test "triage-apply done of a card with no context line moves only the title line" {
  apply_board
  report "$(change done '- [ ] **[alpha] No context**' '')"
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
  [ "$(grep -A3 -F '## ✅ Done' "$V/Boards/alpha.md" | tail -2 | head -1)" = "- [x] **[alpha] No context** ✅ $(date +%F)" ]
  [ "$(grep -A3 -F '## ✅ Done' "$V/Boards/alpha.md" | tail -1)" = '- [x] 🟡 **[alpha] Finished** ✅ 2026-01-01' ]
}

@test "triage-apply title replaces the title line" {
  apply_board
  report "$(change title "$SHIP" "$SHIP_CTX" '- [ ] 🟢 **[alpha] Ship the fix**')"
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
  [ "$(board_diff | grep '^>')" = '> - [ ] 🟢 **[alpha] Ship the fix**' ]
}

@test "triage-apply skips a change whose card text is not found, and applies the others" {
  apply_board
  report "$(change delete '- [ ] 🟡 **[alpha] Gone**' $'\tGone.')" "$(change delete "$SHIP" "$SHIP_CTX")"
  apply
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "triage-apply: applied 1 of 2" ]
  [ "${lines[1]}" = "skipped: - [ ] 🟡 **[alpha] Gone** — not found" ]
  ! grep -q 'Ship it' "$V/Boards/alpha.md"
}

@test "triage-apply skips a card that is on the board twice" {
  apply_board
  report "$(change delete '- [ ] 🟡 **[alpha] Twin**' $'\tSame.')"
  apply
  [ "${lines[0]}" = "triage-apply: applied 0 of 1" ]
  [ "${lines[1]}" = "skipped: - [ ] 🟡 **[alpha] Twin** — found twice" ]
  [ -z "$(board_diff)" ]
}

@test "triage-apply never matches a card in Done" {
  apply_board
  report "$(change delete '- [x] 🟢 **[alpha] Old idea**' $'\tNobody works on it.')"
  apply
  [ "${lines[1]}" = "skipped: - [x] 🟢 **[alpha] Old idea** — not found" ]
}

@test "triage-apply skips a card with the address of a live worker of the board" {
  apply_board
  record_worker block:01a1ef15-4833-735e-9530-226d79648a16 alpha s1
  report "$(change delete '- [ ] 🟠 **[alpha] Busy**' $'\tWorker 01a1ef15 works.')"
  apply
  [ "${lines[1]}" = "skipped: - [ ] 🟠 **[alpha] Busy** — live worker 01a1ef15" ]
  [ -z "$(board_diff)" ]
}

@test "triage-apply skips a second change of the same card" {
  apply_board
  report "$(change context "$SHIP" "$SHIP_CTX" 'New.')" "$(change delete "$SHIP" "$SHIP_CTX")"
  apply
  [ "${lines[0]}" = "triage-apply: applied 1 of 2" ]
  [ "${lines[1]}" = "skipped: $SHIP — changed by an earlier change" ]
  grep -qxF $'\tNew.' "$V/Boards/alpha.md"
}

@test "triage-apply of a report with no jsonl block exits 2 and changes nothing" {
  apply_board
  printf 'RESULT: DONE\n\n## Vault changes\n\n- Move a card.\n' >"$BATS_TEST_TMPDIR/report.md"
  apply
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no jsonl block"* ]]
  [ -z "$(board_diff)" ]
}

@test "triage-apply of a bad line exits 2 and changes nothing" {
  apply_board
  report "$(change delete "$SHIP" "$SHIP_CTX")" '{"op":"move","title_line":"x","context_line":""}'
  apply
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"line 2"* ]]
  [ -z "$(board_diff)" ]
}

@test "triage-apply of a context or title change with no new text exits 2" {
  apply_board
  report "$(change context "$SHIP" "$SHIP_CTX")"
  apply
  [ "$status" -eq 2 ]
  [ -z "$(board_diff)" ]
}

@test "triage-apply writes nothing when the board changes during the run" {
  apply_board
  report "$(change delete "$SHIP" "$SHIP_CTX")"
  export TRIAGE_APPLY_TEST_HOOK="printf -- '- [ ] user edit\n' >>'$V/Boards/alpha.md'"
  apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"the board changed during the run. Nothing written."* ]]
  grep -q 'Ship it' "$V/Boards/alpha.md"
  grep -q 'user edit' "$V/Boards/alpha.md"
}

@test "triage-apply with a missing argument gives the usage" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage-apply alpha
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh triage-apply BOARD REPORT"* ]]
}

# The triage worker: dispatch.sh triage BOARD.

RO=block:01a1ef15-4833-735e-9530-226d79648a16

# triage_setup: the caller is the orchestrator of alpha. The board has a project with a
# git repo, and board resources with MCP servers and rules.
triage_setup() {
  rex_setup
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
  printf -- '---\nrepo: %s\n---\n' "$REPO" >"$V/Projects/alpha.md"
  apply_board
  export BOARD_RESOURCES_HOME="$BATS_TEST_TMPDIR/board-resources"
  mkdir -p "$BOARD_RESOURCES_HOME/alpha"
  printf '{"mcpServers":{"forgejo":{"command":"forgejo-mcp"},"cloudflare-api":{"command":"cf"}}}\n' \
    >"$BOARD_RESOURCES_HOME/alpha/mcp.json"
  printf '{"permissions":{"allow":["Bash(board-ro *)","mcp__cloudflare-api"],"deny":["Bash(pass show *)"]}}\n' \
    >"$BOARD_RESOURCES_HOME/alpha/settings.json"
  rex_orchestrator "$RO" alpha
}

triage() { run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage alpha; }

# wn_args [N]: the arguments of the Nth rex window new call, in RUN_ARGS.
wn_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-window-new-${1:-1}.args"; }

@test "triage starts a worker in the vault, with mode triage and the name triage-<board>" {
  triage_setup
  triage
  [ "$status" -eq 0 ]
  addr=$(sed -n 1p <<<"$output")
  report=$(sed -n 2p <<<"$output")
  [[ "$addr" == block:* ]]
  [[ "$report" == "$XDG_STATE_HOME/board-orchestrator-hc/triage-alpha-"*.md ]]
  wn_args
  [ "$(arg_after --cwd)" = "$V" ]
  has_arg BOARD_NAME=triage-alpha
  [ "$(arg_after -n)" = triage-alpha ]
  session=$(arg_after --session-id)
  [ "$(cat "$XDG_STATE_HOME/board-orchestrator-hc/workers")" = \
    "$(printf '%s\ttriage\talpha\t%s\t%s\t%s\ttriage-alpha' "$addr" "$report" "$session" "$V")" ]
  [ ! -e "$BATS_TEST_TMPDIR/repo-triage-alpha" ]
}

@test "the triage prompt has the brief, the board, the cards file, the repos and the report rules" {
  triage_setup
  triage
  report=$(sed -n 2p <<<"$output")
  wn_args
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == "$(cat "$SKILL_DIR/triage-worker.md")"* ]]
  [[ "$prompt" == *"Board: alpha."* ]]
  [[ "$prompt" == *"Cards file: ${report%.md}-cards.jsonl."* ]]
  [[ "$prompt" == *"Repos: $REPO."* ]]
  [[ "$prompt" == *"write your report to $report"* ]]
  [[ "$prompt" == *"dispatch.sh tell"*"report triage-alpha $report"* ]]
  [[ "$prompt" == *"close triage-alpha"* ]]
  [[ "$prompt" != *"Change only the repo of your card"* ]]
}

@test "the triage cards file has the full line of each card of the open columns" {
  triage_setup
  triage
  report=$(sed -n 2p <<<"$output")
  cards="${report%.md}-cards.jsonl"
  [ "$(wc -l <"$cards")" -eq 8 ]
  [ "$(head -1 "$cards" | jq -r .title_line)" = "$SHIP" ]
  [ "$(head -1 "$cards" | jq -r .context_line)" = "$SHIP_CTX" ]
}

@test "the triage worker settings deny pushes, forge writes, gh api, board-ro, ssh and edits" {
  triage_setup
  triage
  wn_args
  settings=$(arg_after --settings)
  for rule in 'Bash(git push*)' 'Bash(gh pr merge*)' 'Bash(gh pr comment*)' 'Bash(gh issue edit*)' \
    'Bash(gh api*)' 'Bash(board-ro*)' 'Bash(ssh*)' mcp__forgejo__create_issue_comment \
    "Edit(/$V/**)" "Edit(/$REPO/**)"; do
    jq -e --arg r "$rule" '.permissions.deny | index($r)' <<<"$settings" >/dev/null || { echo "deny: $rule"; return 1; }
  done
  for rule in 'Bash(gh pr view*)' 'Bash(git -C * log*)' "Read(/$REPO/**)"; do
    jq -e --arg r "$rule" '.permissions.allow | index($r)' <<<"$settings" >/dev/null || { echo "allow: $rule"; return 1; }
  done
  jq -e '.enabledPlugins["obsidian-second-brain@obsidian-second-brain"] == false' <<<"$settings"
  ! has_arg --permission-mode
}

@test "the triage worker gets only the forge MCP server of the board, found by the board name" {
  triage_setup
  triage
  report=$(sed -n 2p <<<"$output")
  wn_args
  mcp=$(arg_after --mcp-config)
  [ "$mcp" = "${report%.md}-mcp.json" ]
  [ "$(jq -c '.mcpServers | keys' "$mcp")" = '["forgejo"]' ]
}

@test "the triage worker gets no MCP config when the board has no forge server" {
  triage_setup
  printf '{"mcpServers":{"cloudflare-api":{"command":"cf"}}}\n' >"$BOARD_RESOURCES_HOME/alpha/mcp.json"
  triage
  wn_args
  ! has_arg --mcp-config
}

@test "the triage worker gets the deny rules of the board, not its allow rules" {
  triage_setup
  triage
  wn_args
  settings=$(arg_after --settings)
  jq -e '.permissions.deny | index("Bash(pass show *)")' <<<"$settings" >/dev/null
  jq -e '.permissions.allow | (index("mcp__cloudflare-api") or index("Bash(board-ro *)")) | not' <<<"$settings" >/dev/null
}

@test "the triage worker settings deny the other forge writes and the git writes" {
  triage_setup
  triage
  wn_args
  settings=$(arg_after --settings)
  for rule in 'Bash(gh pr review*)' 'Bash(gh issue close*)' 'Bash(gh workflow*)' 'Bash(gh run*)' 'Bash(tea*)' \
    'Bash(git -C * branch -D*)' 'Bash(git -C * reset*)' 'Bash(git -C * checkout*)' 'Bash(git -C * clean*)' \
    'Bash(git -C * commit*)' 'Bash(git -C * worktree remove*)'; do
    jq -e --arg r "$rule" '.permissions.deny | index($r)' <<<"$settings" >/dev/null || { echo "deny: $rule"; return 1; }
  done
}

@test "the triage worker can edit only its report, and send its report" {
  triage_setup
  triage
  report=$(sed -n 2p <<<"$output")
  wn_args
  has_arg "Edit(/$report)"
  has_arg "$(printf 'Bash(%s/.claude/skills/board-orchestrator/dispatch.sh tell *)' "$HOME")"
}

@test "a second triage of the board exits 2 while the first worker runs" {
  triage_setup
  triage
  first=$(sed -n 1p <<<"$output")
  triage
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"a triage worker of alpha runs: $first"* ]]
  [ ! -f "$FAKE_DIR/rex/rex-window-new-2.args" ]
}

@test "a triage of the board starts again when the first worker is gone" {
  triage_setup
  triage
  first=$(sed -n 1p <<<"$output")
  grep -v -F "\"block_id\":\"$first\"" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp" || true
  mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"
  triage
  [ "$status" -eq 0 ]
}

@test "triage from a shell that is not the orchestrator exits 2" {
  triage_setup
  unset REX_BLOCK
  triage
  [ "$status" -eq 2 ]
}

@test "triage of another board than the board of the orchestrator exits 2" {
  triage_setup
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage beta
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"the orchestrator of alpha"* ]]
}

@test "triage starts the cool-down of the triage offer" {
  triage_setup
  triage
  [ "$status" -eq 0 ]
  check
  [[ "$output" == *", last $(date +%F)" ]]
}

@test "close of a triage worker prints its session and removes no folder" {
  triage_setup
  triage
  addr=$(sed -n 1p <<<"$output")
  report=$(sed -n 2p <<<"$output")
  printf 'RESULT: DONE\n' >"$report"
  rex_status "$addr" idle
  wn_args
  session=$(arg_after --session-id)
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" close "$addr"
  [ "$status" -eq 0 ]
  [ "$output" = "$session" ]
  [ -d "$V" ]
  [ -d "$REPO" ]
}

@test "triage-apply reads a jsonl block that is indented in a list item" {
  apply_board
  report "$(change delete "$SHIP" "$SHIP_CTX")"
  sed 's/^/  /; s/^  RESULT/RESULT/; s/^  ## /## /' "$BATS_TEST_TMPDIR/report.md" >"$BATS_TEST_TMPDIR/r2.md"
  mv "$BATS_TEST_TMPDIR/r2.md" "$BATS_TEST_TMPDIR/report.md"
  grep -q '^  ```jsonl' "$BATS_TEST_TMPDIR/report.md"
  apply
  [ "$status" -eq 0 ]
  [ "$output" = "triage-apply: applied 1 of 1" ]
}

@test "triage-apply that cannot write the board exits 1 and says so" {
  apply_board
  report "$(change delete "$SHIP" "$SHIP_CTX")"
  chmod a-w "$V/Boards"
  apply
  chmod u+w "$V/Boards"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"could not write the board"* ]]
  [[ "$output" != *"applied 1"* ]]
  [ -z "$(board_diff)" ]
}

@test "triage-apply applies a report once, and check tells if it is applied" {
  apply_board
  report "$(change delete "$SHIP" "$SHIP_CTX")"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage-apply alpha "$BATS_TEST_TMPDIR/report.md" --check
  [ "$output" = "triage-apply: not applied" ]
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
  printf -- '- [ ] 🟢 **[alpha] Ship it**\n\tPR merged. [[Projects/alpha]]\n' >>"$V/Boards/alpha.md"
  apply
  [ "$status" -eq 0 ]
  [ "$output" = "triage-apply: applied already" ]
  grep -q 'Ship it' "$V/Boards/alpha.md"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" triage-apply alpha "$BATS_TEST_TMPDIR/report.md" --check
  [ "$output" = "triage-apply: applied already" ]
}

@test "a new report of the same triage worker is not applied yet" {
  apply_board
  report "$(change delete "$SHIP" "$SHIP_CTX")"
  apply
  report "$(change delete '- [ ] 🟡 **[alpha] Old idea**' $'\tNobody works on it.')"
  apply
  [ "$output" = "triage-apply: applied 1 of 1" ]
}

@test "report gives the count of the jsonl changes, not the change lines" {
  report "$(change delete "$SHIP" "$SHIP_CTX")" "$(change done '- [ ] 🟡 **[alpha] Old idea**' $'\tNobody works on it.')"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" report "$BATS_TEST_TMPDIR/report.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[jsonl block: 2 changes]"* ]]
  [[ "$output" != *'"op"'* ]]
  [[ "$output" == *"- A note change."* ]]
}
