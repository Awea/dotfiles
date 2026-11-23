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

teardown() { kill_watchers; }

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
  [[ "$prompt" == *"Run a long job"* ]]
  [[ "$prompt" == *"~/.bin/rex-job <job> <dir> -- <command>"* ]]
  [[ "$prompt" == *"rex wait -s <session> <block> --for 3600s --json"* ]]
  [[ "$prompt" == *"rex capture -s <session> -b <block> --trim | tail -40"* ]]
  [[ "$prompt" == *'A time-out gives the error "wait timed out": wait again. When the job ended and you read its end, run ~/.bin/rex-job --done <job>'* ]]
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

@test "close removes the prompt file of the worker" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  f=$(prompt_file s1 'Fix the login bug.') f2=$(prompt_file s2 other)
  dispatch close "$W"
  [ "$status" -eq 0 ]
  [ ! -e "$f" ]
  [ -f "$f2" ]
}

@test "close sweeps the ended jobs and the unused resources in the background" {
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  mkdir -p "$HOME/.bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"%s"\n' "$BATS_TEST_TMPDIR/sweep" >"$HOME/.bin/rex-job"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"%s"\n' "$BATS_TEST_TMPDIR/sweep-resources" >"$HOME/.bin/rex-resource"
  chmod +x "$HOME/.bin/rex-job" "$HOME/.bin/rex-resource"
  dispatch close "$W"
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ ! -s "$BATS_TEST_TMPDIR/sweep" ] || [ ! -s "$BATS_TEST_TMPDIR/sweep-resources" ] || break
    sleep 0.2
  done
  [ "$(cat "$BATS_TEST_TMPDIR/sweep")" = --sweep ]
  [ "$(cat "$BATS_TEST_TMPDIR/sweep-resources")" = --sweep ]
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

@test "notice closed tells the orchestrator that the tab of the worker closed" {
  notice_setup
  : >"$FAKE_DIR/rex/blocks.jsonl"
  fake_block session:fake-1 "$P" window:p-1 orchestrator claude
  dispatch notice "$W" closed
  [ "$status" -eq 0 ]
  rex_args send
  [ "${RUN_ARGS[4]}" = '<rex>d9aef276 worker exited (tab closed). See: dispatch.sh last d9aef276</rex>' ]
  [ "$(jq -r .notice "$STATE/rex/$W.json")" = exited ]
}

@test "an exit and a closed tab of the same worker send one notice" {
  notice_setup
  dispatch notice "$W" exited 0
  dispatch notice "$W" closed
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
}

@test "a closed tab after a blocked notice sends the closed notice" {
  notice_setup
  dispatch notice "$W" blocked "approve Bash"
  dispatch notice "$W" closed
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 2 ]
}

@test "a board stop closes the worker tabs: no notice, and the worker stays resumable" {
  notice_setup
  # stop_board removes the orchestrator record before it kills the session.
  rm "$STATE/orchestrator-garden"
  dispatch notice "$W" closed
  [ -z "$(calls '^rex send ')" ]
  [ "$(jq -r '.notice // "none"' "$STATE/rex/$W.json")" = none ]
}

@test "the watcher sends a closed notice when a block closes" {
  grep -Eq 'rex\.on\("block_closed"' "$SKILL_DIR/board-watch.lua"
  grep -Eq 'notice\(ev\.block_id or ctx\.block_id, "closed"\)' "$SKILL_DIR/board-watch.lua"
}

@test "the watcher sweeps the ended jobs every 10 minutes" {
  grep -Eq 'rex\.every\(600,' "$SKILL_DIR/board-watch.lua"
  grep -Fq '.bin/rex-job"' "$SKILL_DIR/board-watch.lua"
  grep -Fq '"$f" --sweep >/dev/null 2>&1 </dev/null &' "$SKILL_DIR/board-watch.lua"
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

@test "close of a live worker: the closed block sends no notice and leaves no record" {
  rex_garden
  rex_worker "$W" garden s1
  rex_status "$W" idle
  # The watcher hears the closed block, and maybe an exit, while block.close runs.
  printf '#!/bin/sh\n[ "$1" = block.close ] || exit 0\nbash "%s/dispatch.sh" notice "%s" closed >>"%s/notice.out" 2>&1\nbash "%s/dispatch.sh" notice "%s" exited 0 >>"%s/notice.out" 2>&1\nexit 0\n' \
    "$SKILL_DIR" "$W" "$FAKE_DIR" "$SKILL_DIR" "$W" "$FAKE_DIR" >"$FAKE_DIR/rex/on-api"
  chmod +x "$FAKE_DIR/rex/on-api"
  dispatch close "$W"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -f "$STATE/rex/$W.json" ]
  dispatch notice "$W" closed
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

# queue_setup: the orchestrator P of garden, a worker W, and a watcher that delivers the queue.
queue_setup() {
  rex_garden
  rex_worker "$W" garden s1
  OUTBOX="$STATE/rex/outbox-session:fake-1.jsonl"
  queue_watcher session:fake-1 "$OUTBOX"
}

@test "tell puts the message in the queue when the watcher delivers it" {
  queue_setup
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  dispatch tell "report fix-login /r.md"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
  jq -e --arg p "$P" --arg t "<rex from=\"${W: -8} fix-login\">report fix-login /r.md</rex>" \
    '.to == $p and .board == "garden" and .text == $t' "$OUTBOX"
}

@test "tell sends at once when the watcher is an old one with no queue" {
  rex_garden
  queue_watcher session:fake-1
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  dispatch tell "report fix-login /r.md"
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  [ ! -s "$STATE/rex/outbox-session:fake-1.jsonl" ]
}

@test "notice puts the message in the queue and marks the record" {
  queue_setup
  dispatch notice "$W" blocked "approve Bash"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  jq -e --arg p "$P" '.to == $p and .board == "garden"
    and .text == "<rex>d9aef276 worker is blocked (approve Bash). See: dispatch.sh last d9aef276</rex>"' "$OUTBOX"
  [ "$(jq -r .notice "$STATE/rex/$W.json")" = blocked ]
}

# queue_line TO TEXT [BOARD]: a line of the queue.
queue_line() {
  jq -cn --arg t "$1" --arg x "$2" --arg b "${3:-garden}" '{to: $t, board: $b, text: $x}' >>"$OUTBOX"
}

@test "deliver sends the queue when the input box is empty, and empties the queue" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  queue_line "$P" "<rex>two</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  rex_args send
  [ "$(arg_after -b)" = "$P" ]
  [ "${RUN_ARGS[-1]}" = $'\e[200~<rex>one</rex>\n<rex>two</rex>\e[201~' ]
  [ ! -s "$OUTBOX" ]
}

@test "deliver waits until the input box stayed empty for the quiet time" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=60 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
  # The box has stayed empty since the first check.
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
}

@test "deliver sends nothing while the user types, and starts the quiet time again" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=60 dispatch deliver session:fake-1
  screen "${PROMPT}also another task"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
  # The user sent the prompt: the quiet time starts at this check.
  screen "$PROMPT"
  BOARD_OUTBOX_QUIET=60 dispatch deliver session:fake-1
  [ -z "$(calls '^rex send ')" ]
}

@test "deliver sends nothing while the orchestrator is blocked or shows no input box" {
  queue_setup
  rex_status "$P" blocked "approve Bash"
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  rex_status "$P" idle
  screen ' Do you want to proceed?' ' 1. Yes'
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
}

@test "deliver sends to a working orchestrator: Claude Code keeps the message for its next turn" {
  queue_setup
  rex_status "$P" working
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
}

@test "deliver sends to the new orchestrator of the board when the old block is gone" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line block:00000000-0000-0000-0000-00000000dead "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  rex_args send
  [ "$(arg_after -b)" = "$P" ]
  [ ! -s "$OUTBOX" ]
}

@test "deliver drops a message with no live orchestrator, and says it" {
  queue_setup
  rm "$STATE/orchestrator-garden"
  queue_line block:00000000-0000-0000-0000-00000000dead "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -s "$OUTBOX" ]
  [[ "$output" == *"dispatch: no orchestrator of the board garden runs. Dropped: <rex>one</rex>"* ]]
  # The watcher drops the output: the watcher log keeps it.
  grep -Fq "Dropped: <rex>one</rex>" "$STATE/rex/watch-session:fake-1.log"
}

@test "deliver keeps the messages of a busy orchestrator and the messages that come meanwhile" {
  queue_setup
  rex_status "$P" idle
  screen "${PROMPT}typing"
  queue_line "$P" "<rex>one</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  queue_line "$P" "<rex>two</rex>"
  [ "$(jq -r .text "$OUTBOX" | paste -sd, -)" = "<rex>one</rex>,<rex>two</rex>" ]
}

@test "deliver keeps the queue when the send fails" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  FAKE_REX_SEND_FAIL=1 BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
}

@test "deliver with an empty queue does nothing" {
  queue_setup
  dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex ')" ]
}

@test "deliver sends when the box stayed empty for the quiet time since an older check" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  printf '%s\n' "$(($(date +%s) - 100))" >"$OUTBOX.quiet-${P: -8}"
  BOARD_OUTBOX_QUIET=60 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  [ ! -e "$OUTBOX.quiet-${P: -8}" ]
}

@test "deliver starts the quiet time again after the user typed" {
  queue_setup
  rex_status "$P" idle
  queue_line "$P" "<rex>one</rex>"
  printf '%s\n' "$(($(date +%s) - 100))" >"$OUTBOX.quiet-${P: -8}"
  screen "${PROMPT}typing"
  BOARD_OUTBOX_QUIET=60 dispatch deliver session:fake-1
  [ ! -e "$OUTBOX.quiet-${P: -8}" ]
  screen "$PROMPT"
  BOARD_OUTBOX_QUIET=60 dispatch deliver session:fake-1
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
}

@test "a lock of a dead process does not block the queue" {
  queue_setup
  mkdir "$OUTBOX.lock"
  sh -c 'exit 0' &
  dead=$!
  wait "$dead"
  printf '%s\n' "$dead" >"$OUTBOX.lock/pid"
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  start=$(date +%s)
  dispatch tell "report fix-login /r.md"
  [ "$status" -eq 0 ]
  [ $(($(date +%s) - start)) -le 2 ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
  [ ! -e "$OUTBOX.lock" ]
}

@test "a lock of a live process makes tell fail and say it" {
  queue_setup
  mkdir "$OUTBOX.lock"
  printf '%s\n' "$$" >"$OUTBOX.lock/pid"
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  BOARD_OUTBOX_LOCK_TRIES=2 dispatch tell "report fix-login /r.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch: the queue $OUTBOX is locked by $$."* ]]
}

@test "deliver releases the lock after a send fails" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  FAKE_REX_SEND_FAIL=1 BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 1 ]
  [ ! -e "$OUTBOX.lock" ]
}

@test "deliver drops a broken line of the queue and sends the others once" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  printf '{"to": "%s", "board": "gar' "$P" >>"$OUTBOX"
  printf '\n' >>"$OUTBOX"
  queue_line "$P" "<rex>two</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  rex_args send
  [ "${RUN_ARGS[-1]}" = $'\e[200~<rex>one</rex>\n<rex>two</rex>\e[201~' ]
  [ ! -s "$OUTBOX" ]
  [ -z "$(ls "$OUTBOX".tmp.* 2>/dev/null)" ]
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
}

@test "deliver drops the messages when the text went in and only the Enter failed" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  queue_line "$P" "<rex>one</rex>"
  FAKE_REX_KEY_FAIL=1 BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 1 ]
  [ ! -s "$OUTBOX" ]
  [[ "$output" == *"dispatch: the Enter after the message to $P failed. The user must press Enter."* ]]
}

@test "deliver logs once a message that waits for more than 5 minutes" {
  queue_setup
  rex_status "$P" idle
  screen "${PROMPT}typing"
  jq -cn --arg t "$P" --argjson at "$(($(date +%s) - 400))" \
    '{to: $t, board: "garden", text: "<rex>one</rex>", at: $at}' >>"$OUTBOX"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [[ "$output" == *"dispatch: a message to $P waits since"* ]]
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$(grep -c 'waits since' "$STATE/rex/watch-session:fake-1.log")" -eq 1 ]
  # Once sent, a new long wait is logged again.
  screen "$PROMPT"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ ! -e "$OUTBOX.waits-${P: -8}" ]
}

# answer_setup STATE: queue_setup, the caller is the orchestrator P, the worker W has STATE
# and an empty input box, and the answer file a.md.
answer_setup() {
  queue_setup
  export REX_BLOCK=$P REX_SESSION=session:fake-1
  rex_status "$W" "$1"
  screen "$PROMPT"
  printf 'Use main.\n' >"$BATS_TEST_TMPDIR/a.md"
}

# answer_text TEXT: the queued text of an answer TEXT of the orchestrator P.
answer_text() {
  printf '<rex from="%s garden-orchestrator">The user answers through the orchestrator:\n\n%s</rex>' "${P: -8}" "$1"
}

@test "answer puts the words in the queue for a working worker, and says it" {
  answer_setup working
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  [ "$output" = "answer: queued for ${W: -8}: the worker is working. The words go when it is idle." ]
  [ -z "$(calls '^rex send ')" ]
  jq -e --arg w "$W" --arg t "$(answer_text 'Use main.')" \
    '.to == $w and .board == "garden" and .role == "worker" and .text == $t' "$OUTBOX"
}

@test "answer puts the words in the queue for a blocked worker" {
  answer_setup blocked
  dispatch answer "${W: -8}" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  [ "$output" = "answer: queued for ${W: -8}: the worker is blocked. The words go when it is idle." ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(jq -r .to "$OUTBOX")" = "$W" ]
}

@test "answer sends to an idle worker at once, and says it" {
  answer_setup idle
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  [ "$output" = "answer: sent to ${W: -8}." ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  [ ! -s "$OUTBOX" ]
}

@test "answer queues the words for an idle worker whose input box is not empty" {
  answer_setup idle
  screen "${PROMPT}typing"
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  [ "$output" = "answer: queued for ${W: -8}: its input box is not empty. The words go when it is empty." ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(jq -r .to "$OUTBOX")" = "$W" ]
}

@test "answer queues the words for an idle worker that shows no input box" {
  answer_setup idle
  screen ' Do you want to proceed?' ' 1. Yes'
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 0 ]
  [ "$output" = "answer: queued for ${W: -8}: it shows no input box. The words go when it shows an empty one." ]
  [ -z "$(calls '^rex send ')" ]
}

@test "close refuses a worker while words of the user wait for it" {
  answer_setup working
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  rex_status "$W" idle
  screen "${PROMPT}typing"
  dispatch close "$W"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch: words of the user wait for the worker in $W. Close nothing."* ]]
  [ -z "$(calls '^rex kill ')" ]
  grep -q "$W" "$STATE/workers"
}

@test "answer queues the words for an idle worker after its older queued words" {
  answer_setup working
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  rex_status "$W" idle
  printf 'Then push.\n' >"$BATS_TEST_TMPDIR/b.md"
  dispatch answer "$W" "$BATS_TEST_TMPDIR/b.md"
  [ "$status" -eq 0 ]
  [ "$output" = "answer: queued for ${W: -8}: older words wait for it. The words go after them." ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(jq -r .text "$OUTBOX" | grep -c 'The user answers')" -eq 2 ]
}

@test "answer to a busy worker sends nothing when no watcher delivers the queue" {
  queue_setup
  kill_watchers
  export REX_BLOCK=$P REX_SESSION=session:fake-1
  rex_status "$W" working
  printf 'Use main.\n' >"$BATS_TEST_TMPDIR/a.md"
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.md"
  [ "$status" -eq 1 ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -s "$OUTBOX" ]
}

# worker_line TEXT: a queued answer to the worker W.
worker_line() {
  jq -cn --arg t "$W" --arg x "$1" '{to: $t, board: "garden", role: "worker", text: $x}' >>"$OUTBOX"
}

@test "deliver keeps the words of a working or blocked worker, and sends to the orchestrator" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  worker_line "<rex>one</rex>"
  queue_line "$P" "<rex>notice</rex>"
  for st in working blocked; do
    rex_status "$W" "$st"
    BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
    [ "$status" -eq 0 ]
  done
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  rex_args send
  [ "$(arg_after -b)" = "$P" ]
  [ "$(jq -r .to "$OUTBOX")" = "$W" ]
}

@test "deliver sends nothing to an idle worker that shows a dialog or typed text" {
  queue_setup
  rex_status "$W" idle
  worker_line "<rex>one</rex>"
  screen ' Do you want to proceed?' ' 1. Yes'
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  screen "${PROMPT}typing"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$OUTBOX")" -eq 1 ]
}

# delivers_in_order STATE: deliver sends the two queued words to the worker W with STATE as
# one input, in their order.
delivers_in_order() {
  queue_setup
  rex_status "$W" "$1"
  screen "$PROMPT"
  worker_line "<rex>one</rex>"
  worker_line "<rex>two</rex>"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  rex_args send
  [ "$(arg_after -b)" = "$W" ]
  [ "${RUN_ARGS[-1]}" = $'\e[200~<rex>one</rex>\n<rex>two</rex>\e[201~' ]
  [ ! -s "$OUTBOX" ]
}

@test "deliver sends the words to an idle worker in their order" { delivers_in_order idle; }

@test "deliver sends the words to a done worker" { delivers_in_order done; }

@test "deliver drops the words to a gone worker, and does not send them to the orchestrator" {
  queue_setup
  rex_status "$P" idle
  screen "$PROMPT"
  dead=block:00000000-0000-0000-0000-00000000dead
  jq -cn --arg t "$dead" '{to: $t, board: "garden", role: "worker", text: "<rex>one</rex>"}' >>"$OUTBOX"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ ! -s "$OUTBOX" ]
  [[ "$output" == *"dispatch: the worker $dead is gone. Dropped: <rex>one</rex>"* ]]
}

@test "deliver keeps the words to a worker when Rex does not answer" {
  queue_setup
  worker_line "<rex>one</rex>"
  FAKE_REX_FAIL=1 BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ -z "$(calls '^rex send ')" ]
  [ "$(jq -r .to "$OUTBOX")" = "$W" ]
}

@test "deliver removes the quiet and wait marks of a gone worker" {
  queue_setup
  dead=block:00000000-0000-0000-0000-00000000dead
  jq -cn --arg t "$dead" '{to: $t, board: "garden", role: "worker", text: "<rex>one</rex>"}' >>"$OUTBOX"
  : >"$OUTBOX.quiet-${dead: -8}"
  : >"$OUTBOX.waits-${dead: -8}"
  BOARD_OUTBOX_QUIET=0 dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ ! -e "$OUTBOX.quiet-${dead: -8}" ]
  [ ! -e "$OUTBOX.waits-${dead: -8}" ]
}

@test "tell writes the time of the message in the queue" {
  queue_setup
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  dispatch tell "report fix-login /r.md"
  [ "$(($(date +%s) - $(jq -r .at "$OUTBOX")))" -le 2 ]
}

@test "a command of the orchestrator replaces an old watcher of its session" {
  rex_garden
  export REX_BLOCK=$P REX_SESSION=session:fake-1
  fake_spawners
  queue_watcher session:fake-1
  old=$(cat "$STATE/rex/watch-session:fake-1.pid")
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_DIR/spawn.log")" -eq 1 ]
  grep -q 'board-watch.lua .* outbox=' "$FAKE_DIR/spawn.log"
  sleep 0.2
  ! ps -o args= -p "$old" | grep -q board-watch
}

@test "a command of the orchestrator keeps a watcher that delivers the queue, and starts none" {
  rex_garden
  export REX_BLOCK=$P REX_SESSION=session:fake-1
  fake_spawners
  queue_watcher session:fake-1 "$STATE/rex/outbox-session:fake-1.jsonl"
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_DIR/spawn.log" ]
  kill_watchers
  dispatch workers garden
  [ ! -s "$FAKE_DIR/spawn.log" ]
}

@test "a worker never replaces the watcher" {
  rex_garden
  rex_worker "$W" garden s1
  fake_spawners
  queue_watcher session:fake-1
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  dispatch tell "report fix-login /r.md"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_DIR/spawn.log" ]
}
