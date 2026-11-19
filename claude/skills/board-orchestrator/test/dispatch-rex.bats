#!/usr/bin/env bats
# dispatch.sh in Renux: start, close, last, remind, answer, send, resumable and tell.

bats_require_minimum_version 1.5.0
load helper

O=block:01a1ef15-4833-735e-9530-226d79648a16
W=block:01a1ef1f-4f92-7b07-8a51-9be2d9aef276
P=block:01a1ef2a-0000-7000-8000-000000000001

setup() {
  rex_setup
  REPO="$BATS_TEST_TMPDIR/repo"
  repo_with_push_policy "$REPO"
  printf 'Fix the login bug.\n' >"$BATS_TEST_TMPDIR/p.md"
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$STATE"
}

dispatch() { run bash "$SKILL_DIR/dispatch.sh" "$@"; }
start() { dispatch start "${1:-task}" "$REPO" "Fix login" "$BATS_TEST_TMPDIR/p.md"; }

# rex_args CMD [N]: the arguments of the Nth saved call, one for each element of RUN_ARGS.
rex_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-$1-${2:-1}.args"; }

# sent_text [N]: the text of the Nth rex send call.
sent_text() { rex_args send "${1:-1}"; printf '%s' "${RUN_ARGS[-1]}"; }

@test "caller_board reads the record of REX_BLOCK" {
  rex_orchestrator "$O" garden
  start
  [ "$status" -eq 0 ]
  rex_args window-new
  has_arg BOARD=garden
}

@test "caller_board fails for a block with no record" {
  rex_orchestrator "$O" garden
  rm "$STATE/rex/$O.json"
  start
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a board orchestrator"* ]]
}

@test "caller_board names REX_BLOCK when it is empty on a forced Rex" {
  export BOARD_TERM=rex
  start
  [ "$status" -eq 2 ]
  [[ "$output" == *"dispatch: REX_BLOCK is empty. Run this in the board orchestrator."* ]]
}

@test "start opens a worker window with the tell rule and the tell footer" {
  rex_orchestrator "$O" garden
  start
  [ "$status" -eq 0 ]
  new=$(sed -n 1p <<<"$output")
  [[ "$new" == block:* ]]
  rex_args window-new
  has_arg --focus=false
  has_arg BOARD_ROLE=worker
  has_arg "BOARD_ORCHESTRATOR=$O"
  has_arg "Bash($HOME/.claude/skills/board-orchestrator/dispatch.sh tell *)"
  [[ "$HOME" == /* ]]
  prompt=${RUN_ARGS[-1]}
  report=$(sed -n 2p <<<"$output")
  [[ "$prompt" == *"run: $HOME/.claude/skills/board-orchestrator/dispatch.sh tell \"report fix-login $report\""* ]]
  [[ "$prompt" == *"dispatch.sh tell \"close fix-login\""* ]]
  for a in "${RUN_ARGS[@]}"; do [[ "$a" != *"hc send"* ]]; done
  [[ "$prompt" == *"Run a long job"* ]]
  [[ "$prompt" == *"~/.bin/rex-job <job> <dir> -- <command>"* ]]
  [[ "$prompt" == *"rex wait <block> --for 3600s --json"* ]]
  [[ "$prompt" == *"rex capture -s <session> -b <block> --trim | tail -40"* ]]
  [[ "$prompt" != *"hc "* ]]
  grep -q "^$new"$'\t' "$STATE/workers"
}

@test "unique_name checks the window labels of the session" {
  rex_orchestrator "$O" garden
  fake_block session:fake-1 "$W" window:w-1 fix-login claude
  start
  [ "$status" -eq 0 ]
  rex_args window-new
  has_arg BOARD_NAME=fix-login-2
}

@test "start says rex when the worker does not start" {
  rex_orchestrator "$O" garden
  export REX_SESSION=
  start
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch: rex did not start the worker."* ]]
}

@test "tell wraps the text and sends it to the orchestrator" {
  fake_block session:fake-1 "$O" window:fake-1 orchestrator claude
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$O
  dispatch tell "report fix-login /r.md"
  [ "$status" -eq 0 ]
  [ "$(sent_text)" = "<rex from=\"${W: -8} fix-login\">report fix-login /r.md</rex>" ]
  rex_args send
  [ "$(arg_after -b)" = "$O" ]
}

@test "tell keeps quotes, dollar signs and newlines in one argument" {
  fake_block session:fake-1 "$O" window:fake-1 orchestrator claude
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$O
  text=$'close "x" $HOME `id`\nsecond line'
  dispatch tell "$text"
  [ "$status" -eq 0 ]
  [ "$(sent_text)" = $'\e[200~'"<rex from=\"${W: -8} fix-login\">$text</rex>"$'\e[201~' ]
  [ "$(ls "$FAKE_DIR"/rex/rex-send-*.args | wc -l)" -eq 1 ]
}

@test "tell refuses outside a Renux worker" {
  dispatch tell "report x /r.md"
  [ "$status" -eq 2 ]
  [ "$output" = "dispatch: tell runs only in a board worker in Renux." ]
  export REX_SESSION=session:fake-1
  dispatch tell "report x /r.md"
  [ "$status" -eq 2 ]
}

@test "tell fails when the orchestrator does not get the text" {
  fake_block session:fake-1 "$O" window:fake-1 orchestrator claude
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$O
  export FAKE_REX_SEND_FAIL=1
  dispatch tell "report x /r.md"
  [ "$status" -eq 1 ]
}

@test "close waits until the worker is not working, then closes the block" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  dispatch close "$W"
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
  [ -n "$(calls 'api call block.close')" ]
  [ ! -f "$STATE/rex/$W.json" ]
  ! grep -q "$W" "$STATE/workers"
}

@test "close gives up while the worker works" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" working
  export BOARD_CLOSE_WAIT=0
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" close "$W"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"still working"* ]]
  [ -z "$(calls 'api call block.close')" ]
  [ -f "$STATE/rex/$W.json" ]
}

@test "close of a block the user already closed removes the record and prints the session" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  grep -v -F "\"block_id\":\"$W\"" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp"
  mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"
  dispatch close "$W"
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
  [ ! -f "$STATE/rex/$W.json" ]
  ! grep -q "$W" "$STATE/workers"
  [ -z "$(calls 'api call block.close')" ]
}

@test "close by the short ID removes the workers line" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  dispatch close "${W: -8}"
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
  [ -n "$(calls 'api call block.close')" ]
  [ ! -f "$STATE/rex/$W.json" ]
  ! grep -q "$W" "$STATE/workers"
}

@test "close by the short ID of an exited worker removes the line and prints the session" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  grep -v -F "\"block_id\":\"$W\"" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp"
  mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"
  dispatch close "${W: -8}"
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
  [ ! -f "$STATE/rex/$W.json" ]
  ! grep -q "$W" "$STATE/workers"
}

@test "remind and answer take the short ID" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  dispatch remind "${W: -8}" /r.md
  [ "$status" -eq 0 ]
  rex_args send
  [ "$(arg_after -b)" = "$W" ]
  printf 'yes\n' >"$BATS_TEST_TMPDIR/a.md"
  dispatch answer "${W: -8}" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  rex_args send 2
  [ "$(arg_after -b)" = "$W" ]
}

@test "last of an exited worker reads the session jsonl of its workers line" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  # The block and its record are gone.
  grep -v -F "\"block_id\":\"$W\"" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp"
  mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"
  rm "$STATE/rex/$W.json"
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Done, see the PR."}]}}' \
    >"$HOME/.claude/projects/p/s1.jsonl"
  dispatch last "${W: -8}"
  [ "$status" -eq 0 ]
  [ "$output" = "Done, see the PR." ]
  dispatch last "$W"
  [ "$status" -eq 0 ]
  [ "$output" = "Done, see the PR." ]
}

@test "last of a block with no workers line says no agent" {
  rex_orchestrator "$O" garden
  dispatch last deadbeef
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agent in deadbeef"* ]]
}

@test "resumable marks the record of a lost worker before it closes the block" {
  rex_garden
  rex_worker "$W" garden s1
  cp "$SKILL_DIR/test/fixtures/rex/process-shell.json" "$FAKE_DIR/rex/process-$W.json"
  # The watcher hears the exit while block.close runs.
  printf '#!/bin/sh\n[ "$1" = block.close ] && bash "%s/dispatch.sh" notice "%s" exited 0 >>"%s/notice.out" 2>&1\nexit 0\n' \
    "$SKILL_DIR" "$W" "$FAKE_DIR" >"$FAKE_DIR/rex/on-api"
  chmod +x "$FAKE_DIR/rex/on-api"
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ -n "$(calls 'api call block.close')" ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -f "$STATE/rex/$W.json" ]
}

@test "close keeps everything when Rex does not answer" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  export FAKE_REX_FAIL=1
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" close "$W"
  [ "$status" -eq 1 ]
  [ -f "$STATE/rex/$W.json" ]
  grep -q "$W" "$STATE/workers"
}

@test "close refuses a block that is not a worker" {
  rex_orchestrator "$O" garden
  dispatch close "$O"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agent in"* ]]
}

@test "last reads the session jsonl, else the capture" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  printf 'line on screen\n' >"$FAKE_DIR/rex/capture.txt"
  dispatch last "$W"
  [ "$output" = "line on screen" ]
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Which branch?"}]}}' \
    >"$HOME/.claude/projects/p/s1.jsonl"
  dispatch last "$W"
  [ "$output" = "Which branch?" ]
}

@test "remind and answer send a wrapped message" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  dispatch remind "$W" /r.md
  [ "$status" -eq 0 ]
  [ "$(sent_text 1)" = "<rex from=\"${O: -8} garden-orchestrator\">Write the report again to /r.md now, in one Write call. Give the full report for the current state, with a new first line in the same form as before. The new report replaces the old one.</rex>" ]
  printf 'Use "main"\nthen push\n' >"$BATS_TEST_TMPDIR/a.md"
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  [ "$(sent_text 2)" = $'\e[200~'"<rex from=\"${O: -8} garden-orchestrator\">The user answers through the orchestrator:"$'\n\n'"Use \"main\""$'\n'"then push</rex>"$'\e[201~' ]
}

@test "remind sends nothing to a worker that works" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" working
  dispatch remind "$W" /r.md
  [ "$status" -eq 1 ]
  [ -z "$(calls '^rex send ')" ]
}

# card_setup: the card file and a vault with two boards.
card_setup() {
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  for b in garden work; do
    printf -- '---\nkanban-plugin: board\n---\n\n## Backlog\n' >"$OBSIDIAN_VAULT_PATH/Boards/$b.md"
  done
  CARD="$BATS_TEST_TMPDIR/card.md"
  printf '%s\n%s\n' $'- [ ] 🟢 **[dotfiles] Fix the login**' $'\tThe login fails.' >"$CARD"
}

# rex_garden: a live Renux orchestrator $P of the board garden, with its record.
rex_garden() {
  fake_block session:fake-1 "$P" window:p-1 orchestrator claude
  rex_record_file "$P" '{"board":"garden","role":"orchestrator","rex_session":"session:fake-1","window":"window:p-1"}'
  printf '%s\tgarden\n' "$P" >"$STATE/orchestrator-garden"
}

@test "send to a board that runs on Rex uses the Rex message" {
  card_setup
  rex_orchestrator "$O" work
  rex_garden
  dispatch send garden start "$CARD"
  [ "$status" -eq 0 ]
  id=$(basename "$(find "$STATE/queue/garden" -name '*.json')" .json)
  [ "$output" = "send: $id sent to $P" ]
  [ "$(sent_text)" = "<rex from=\"${O: -8} work-orchestrator\">card $id</rex>" ]
  [ "$(jq -r .from_address "$STATE/queue/garden/$id.json")" = "$O" ]
}

@test "send from Rex to an hc board uses hc send" {
  card_setup
  rex_orchestrator "$O" work
  fake_terminal t2 garden orchestrator
  printf 't2\tgarden\n' >"$STATE/orchestrator-garden"
  dispatch send garden start "$CARD"
  [ "$status" -eq 0 ]
  id=$(basename "$(find "$STATE/queue/garden" -name '*.json')" .json)
  [ -n "$(calls "^hc send t2 card $id\$")" ]
  [ -z "$(calls '^rex send ')" ]
}

@test "a failed send to a Rex orchestrator keeps the queue file" {
  card_setup
  rex_orchestrator "$O" work
  rex_garden
  export FAKE_REX_SEND_FAIL=1
  dispatch send garden start "$CARD"
  [ "$status" -eq 0 ]
  id=$(basename "$(find "$STATE/queue/garden" -name '*.json')" .json)
  [[ "$output" == *"send: $id queued, rex send to $P failed" ]]
  [ -f "$STATE/queue/garden/$id.json" ]
}

@test "resumable drops a worker block that has an idle shell" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  cp "$SKILL_DIR/test/fixtures/rex/process-shell.json" "$FAKE_DIR/rex/process-$W.json"
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ -n "$(calls 'api call block.close')" ]
  [ ! -f "$STATE/rex/$W.json" ]
}

# notice_setup: an orchestrator and a worker W of the board garden.
notice_setup() {
  rex_garden
  rex_worker "$W" garden s1
}

@test "notice sends one blocked message to the orchestrator" {
  notice_setup
  dispatch notice "$W" blocked "approve Bash: touch /tmp/x"
  [ "$status" -eq 0 ]
  rex_args send
  [ "${RUN_ARGS[3]}" = "$P" ]
  [ "${RUN_ARGS[4]}" = '<rex>d9aef276 worker is blocked (approve Bash: touch /tmp/x). See: dispatch.sh last d9aef276</rex>' ]
  [ "$(jq -r .notice "$STATE/rex/$W.json")" = blocked ]
}

@test "a second blocked notice sends nothing" {
  notice_setup
  dispatch notice "$W" blocked "approve Bash"
  dispatch notice "$W" blocked "approve Bash"
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
}

@test "working clears it, so the next blocked sends again" {
  notice_setup
  dispatch notice "$W" blocked "approve Bash"
  dispatch notice "$W" working ""
  [ "$status" -eq 0 ]
  [ "$(jq -r '.notice // "none"' "$STATE/rex/$W.json")" = none ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  dispatch notice "$W" blocked "approve Bash"
  [ "$(calls '^rex send ' | wc -l)" -eq 2 ]
}

@test "notice exited gives the exit code and works after the block is gone" {
  notice_setup
  : >"$FAKE_DIR/rex/blocks.jsonl"
  fake_block session:fake-1 "$P" window:p-1 orchestrator claude
  dispatch notice "$W" exited 3
  [ "$status" -eq 0 ]
  rex_args send
  [ "${RUN_ARGS[4]}" = '<rex>d9aef276 worker exited (exit 3). See: dispatch.sh last d9aef276</rex>' ]
  [ "$(jq -r .notice "$STATE/rex/$W.json")" = exited ]
}

@test "notice for a block with no record does nothing" {
  notice_setup
  dispatch notice block:00000000-0000-0000-0000-00000000dead blocked "x"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
}

@test "notice for the orchestrator block does nothing" {
  notice_setup
  dispatch notice "$P" blocked "x"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
}

@test "a failed send keeps the notice open for the next try" {
  notice_setup
  export FAKE_REX_SEND_FAIL=1
  dispatch notice "$W" blocked "x"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.notice // "none"' "$STATE/rex/$W.json")" = none ]
}

@test "close of a live worker: the exit that the kill causes sends no notice and leaves no record" {
  rex_garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  # The watcher hears the exit while block.close runs.
  printf '#!/bin/sh\n[ "$1" = block.close ] && bash "%s/dispatch.sh" notice "%s" exited 0 >>"%s/notice.out" 2>&1\nexit 0\n' \
    "$SKILL_DIR" "$W" "$FAKE_DIR" >"$FAKE_DIR/rex/on-api"
  chmod +x "$FAKE_DIR/rex/on-api"
  dispatch close "$W"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -f "$STATE/rex/$W.json" ]
  dispatch notice "$W" exited 0
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -f "$STATE/rex/$W.json" ]
}

@test "notice cleans the detail: no newline, and a missing exit code gives ?" {
  notice_setup
  dispatch notice "$W" blocked $'line one\nline two'
  rex_args send
  [ "${RUN_ARGS[4]}" = '<rex>d9aef276 worker is blocked (line one line two). See: dispatch.sh last d9aef276</rex>' ]
  rm "$FAKE_DIR/rex/rex-send-1.args"; rm -f "$FAKE_DIR/rex/n-args-send"
  dispatch notice "$W" exited ""
  rex_args send
  [ "${RUN_ARGS[4]}" = '<rex>d9aef276 worker exited (exit ?). See: dispatch.sh last d9aef276</rex>' ]
}

@test "start footer tells a Rex worker not to change the Renux window" {
  rex_orchestrator "$O" garden
  start
  [ "$status" -eq 0 ]
  rex_args window-new
  prompt=${RUN_ARGS[-1]}
  [[ "$prompt" == *"Do not change the Renux window."* ]]
  [[ "$prompt" != *"herdr-app window"* ]]
}

# setup_runs: the worker W runs worktree-setup.sh: bash in front, and a log with no exit line.
setup_runs() {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  cp "$SKILL_DIR/test/fixtures/rex/process-setup.json" "$FAKE_DIR/rex/process-$W.json"
  printf 'worktree-setup: make worktree-setup in /x\n' >"$STATE/fix-login-1-worktree-setup.log"
}

@test "resumable keeps a worker block while its worktree-setup runs" {
  setup_runs
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(calls 'api call block.close')" ]
  [ -f "$STATE/rex/$W.json" ]
}

@test "workers lists a worker while its worktree-setup runs" {
  setup_runs
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .address <<<"$output")" = "$W" ]
}

@test "resumable drops a worker block whose worktree-setup ended and left a shell" {
  setup_runs
  printf 'worktree-setup: exit 0\n' >>"$STATE/fix-login-1-worktree-setup.log"
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ -n "$(calls 'api call block.close')" ]
}
