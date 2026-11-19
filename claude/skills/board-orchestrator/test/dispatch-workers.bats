#!/usr/bin/env bats
# dispatch.sh workers, resumable, resume, resume-clear, close, last, remind, answer.

bats_require_minimum_version 1.5.0
load helper

dispatch() { run bash "$SKILL_DIR/dispatch.sh" "$@"; }
records() { cat "$XDG_STATE_HOME/board-orchestrator-hc/workers"; }

# lost_worker ADDR BOARD SESSION [FOREGROUND [EXTRA_LABELS_JSON]]: a worker record and its
# kept terminal after a restart: hc put a shell in the place of claude, with the same
# labels. FOREGROUND is the program in front of that shell (default: the shell).
lost_worker() {
  local f="$FAKE_DIR/hc-get-$1.json" extra=${5:-'{}'}
  fake_terminal "$1" "$2" worker "${4:-zsh}" "$(jq -c --arg s "$3" '{"board.session":$s} + .' <<<"$extra")"
  jq --arg fg "${4:-zsh}" '.argv = ["/usr/bin/zsh"] | .pid = 300 | .keep = true
    | .foreground.pid = (if $fg == "zsh" then 300 else 512 end)' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  record_worker "$1" "$2" "$3"
}

@test "workers lists a live worker of the board" {
  live_worker t9 garden s1
  set_status t9 idle
  printf 'RESULT: DONE\n## Result\n' >"$XDG_STATE_HOME/board-orchestrator-hc/fix-login-1.md"
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .address <<<"$output")" = t9 ]
  [ "$(jq -r .name <<<"$output")" = fix-login ]
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ "$(jq -r .mode <<<"$output")" = task ]
  [ "$(jq -r .report_exists <<<"$output")" = true ]
  [ "$(jq -r .first_line <<<"$output")" = "RESULT: DONE" ]
  [ "$(jq -r .waits <<<"$output")" = false ]
}

@test "workers says waits for a blocked worker" {
  live_worker t9 garden s1
  set_status t9 blocked
  dispatch workers garden
  [ "$(jq -r .waits <<<"$output")" = true ]
}

@test "workers skips a stale record" {
  record_worker t9 garden s1
  fake_terminal t9 lab worker claude '{"board.session":"s1"}'
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workers skips a terminal with another session" {
  record_worker t9 garden s1
  fake_terminal t9 garden worker claude '{"board.session":"s2"}'
  dispatch workers garden
  [ -z "$output" ]
}

@test "workers skips a worker that a restart replaced with a shell" {
  lost_worker t9 garden s1
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workers lists a worker that the user started again in its shell" {
  lost_worker t9 garden s1 claude
  dispatch workers garden
  [ "$(jq -r .address <<<"$output")" = t9 ]
}

@test "workers lists a worker that runs the program of dispatch" {
  live_worker t9 garden s1
  f="$FAKE_DIR/hc-get-t9.json"
  jq '.argv = ["env", "BOARD_RESOURCES_OFF=1", "claude"] | .pid = 300 | .foreground = {name: "claude", pid: 300}' \
    "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  dispatch workers garden
  [ "$(jq -r .address <<<"$output")" = t9 ]
}

@test "resumable lists a worker that a restart replaced with a shell, and closes that shell" {
  lost_worker t9 garden s1 zsh '{"herdr.tab":"tb3"}'
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .session <<<"$output")" = s1 ]
  park=$(grep -n -m 1 'terminal.park --terminal t9' "$FAKE_LOG" | cut -d: -f1)
  kill=$(grep -n -m 1 '^hc kill t9' "$FAKE_LOG" | cut -d: -f1)
  [ -n "$park" ] && [ -n "$kill" ]
  [ "$park" -lt "$kill" ]
  [ -n "$(calls '^hc rm t9')" ]
  [ "$(records | cut -f5)" = s1 ]
}

@test "resumable closes no terminal of another session" {
  lost_worker t9 garden s2
  : >"$XDG_STATE_HOME/board-orchestrator-hc/workers"
  record_worker t9 garden s0
  dispatch resumable garden
  [ "$(jq -r .session <<<"$output")" = s0 ]
  [ -z "$(calls '^hc (kill|rm)')" ]
}

@test "resume closes the shell that a restart left in the place of the worker" {
  orchestrator t5 garden
  repo_with_push_policy "$BATS_TEST_TMPDIR/repo"
  lost_worker t9 garden s1
  FAKE_RUN_ADDR=t12 dispatch resume garden s1
  [ "$status" -eq 0 ]
  kill=$(grep -n -m 1 '^hc kill t9' "$FAKE_LOG" | cut -d: -f1)
  run=$(grep -n -m 1 '^hc run' "$FAKE_LOG" | cut -d: -f1)
  [ -n "$kill" ] && [ -n "$run" ]
  [ "$kill" -lt "$run" ]
  [ -n "$(calls '^hc rm t9')" ]
  [ "$(records | cut -f1)" = t12 ]
}

@test "resume-clear drops the record of a worker that a restart replaced with a shell, and closes that shell" {
  lost_worker t9 garden s1
  dispatch resume-clear garden
  [ "$status" -eq 0 ]
  [ -z "$(records)" ]
  [ -n "$(calls '^hc kill t9')" ]
  [ -n "$(calls '^hc rm t9')" ]
}

@test "a worker terminal with no argv and a shell in front still runs" {
  live_worker t9 garden s1
  f="$FAKE_DIR/hc-get-t9.json"
  jq '.foreground = {name: "zsh", pid: 300} | .pid = 300' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  dispatch workers garden
  [ "$(jq -r .address <<<"$output")" = t9 ]
  dispatch resumable garden
  [ -z "$output" ]
  [ -z "$(calls '^hc (kill|rm)')" ]
}

@test "resumable lists a lost worker shell that runs a program, and does not close it" {
  lost_worker t9 garden s1 vim
  dispatch resumable garden
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ -z "$(calls '^hc (kill|rm)')" ]
  [ -z "$(calls 'terminal.park')" ]
}

@test "resumable lists a worker whose terminal is gone" {
  record_worker t9 garden s1
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ "$(jq -r .name <<<"$output")" = fix-login ]
  [ "$(jq -r .mode <<<"$output")" = task ]
  [ "$(jq -r .cwd <<<"$output")" = "$BATS_TEST_TMPDIR/repo" ]
}

@test "resumable gives the report fields and done" {
  record_worker t9 garden s1
  printf 'RESULT: DONE\n' >"$XDG_STATE_HOME/board-orchestrator-hc/fix-login-1.md"
  dispatch resumable garden
  [ "$(jq -r .report_exists <<<"$output")" = true ]
  [ "$(jq -r .first_line <<<"$output")" = "RESULT: DONE" ]
  [ "$(jq -r .done <<<"$output")" = true ]
}

@test "resumable skips a live worker and another board" {
  live_worker t9 garden s1
  record_worker t8 lab s2
  dispatch resumable garden
  [ -z "$output" ]
}

@test "resume starts with --resume and the cut-turn prompt" {
  orchestrator t5 garden
  repo_with_push_policy "$BATS_TEST_TMPDIR/repo"
  record_worker t9 garden s1
  FAKE_RUN_ADDR=t12 dispatch resume garden s1
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p <<<"$output")" = t12 ]
  run_args
  [ "$(arg_after --resume)" = s1 ]
  has_arg board.session=s1
  [ "${RUN_ARGS[-2]}" = -- ]
  [[ "${RUN_ARGS[-1]}" == "The stop of the board orchestrator cut your turn. Continue the task. If you waited for an answer from the user, ask again."* ]]
  [ "$(records | cut -f1)" = t12 ]
}

@test "resume gives the address of the new orchestrator" {
  orchestrator t6 garden
  repo_with_push_policy "$BATS_TEST_TMPDIR/repo"
  record_worker t9 garden s1 /r.md
  dispatch resume garden s1
  run_args
  has_arg 'Bash(hc send t6 *)'
  [[ "${RUN_ARGS[-1]}" == *'After you write the report, run: hc send t6 "report fix-login /r.md"'* ]]
}

@test "resume exits 1 for an unknown session" {
  orchestrator t5 garden
  dispatch resume garden nope
  [ "$status" -eq 1 ]
  [ -z "$(calls '^hc run')" ]
}

@test "resume-clear drops the records that are not live" {
  record_worker t8 garden s0
  live_worker t9 garden s1
  record_worker t7 lab s2
  dispatch resume-clear garden
  [ "$status" -eq 0 ]
  [ "$(records | cut -f5 | tr '\n' ' ')" = "s1 s2 " ]
}

@test "resume-clear SESSION drops only that record" {
  record_worker t8 garden s0
  record_worker t7 garden s3
  dispatch resume-clear garden s0
  [ "$(records | cut -f5)" = s3 ]
}

@test "close waits, ends the worker and drops its record" {
  live_worker t9 garden s1
  dispatch close t9
  [ "$status" -eq 0 ]
  [ -n "$(calls '^hc wait t9 --timeout 90')" ]
  [ -n "$(calls '^hc kill t9')" ]
  [ -n "$(calls '^hc rm t9')" ]
  [ -z "$(records)" ]
}

@test "close prints the claude session ID of the worker" {
  live_worker t9 garden s1
  dispatch close t9
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
}

@test "close waits again when a message ends the wait" {
  live_worker t9 garden s1
  printf '%s\n' '{"ended":false,"reason":"message"}' >"$FAKE_DIR/hc-wait.json"
  set_status t9 working
  dispatch close t9
  [ "$status" -eq 1 ]
  [[ "$output" == *"still working"* ]]
  [ -z "$(calls '^hc kill')" ]
  [ "$(calls '^hc wait t9' | wc -l)" -ge 2 ]
}

@test "close closes nothing when the worker still works after 90 s" {
  live_worker t9 garden s1
  printf '%s\n' '{"ended":false,"reason":"timeout"}' >"$FAKE_DIR/hc-wait.json"
  set_status t9 working
  dispatch close t9
  [ "$status" -eq 1 ]
  [[ "$output" == *"still working"* ]]
  [ -z "$(calls '^hc kill')" ]
  [ -n "$(records)" ]
}

@test "close cleans up a worker that exited" {
  live_worker t9 garden s1
  jq '.state = "finished"' "$FAKE_DIR/hc-get-t9.json" >"$FAKE_DIR/x" && mv "$FAKE_DIR/x" "$FAKE_DIR/hc-get-t9.json"
  dispatch close t9
  [ "$status" -eq 0 ]
  [ "$output" = s1 ]
  [ -z "$(calls '^hc wait')" ]
  [ -z "$(calls '^hc kill')" ]
  [ -n "$(calls '^hc rm t9')" ]
  [ -z "$(records)" ]
}

@test "close parks a worker that has its own pane" {
  fake_terminal t9 garden worker claude '{"board.session":"s1","herdr.tab":"tb3"}'
  record_worker t9 garden s1
  dispatch close t9
  [ "$status" -eq 0 ]
  park=$(grep -n -m 1 'terminal.park --terminal t9' "$FAKE_LOG" | cut -d: -f1)
  kill=$(grep -n -m 1 '^hc kill t9' "$FAKE_LOG" | cut -d: -f1)
  [ -n "$park" ] && [ -n "$kill" ]
  [ "$park" -lt "$kill" ]
}

@test "close does not park a hidden worker" {
  live_worker t9 garden s1
  dispatch close t9
  [ "$status" -eq 0 ]
  [ -z "$(calls 'terminal.park')" ]
}

@test "close refuses an address that is not a worker" {
  fake_terminal t5 garden orchestrator
  dispatch close t5
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agent"* ]]
  [ -z "$(calls '^hc kill')" ]
}

@test "last prints the last assistant text of the transcript" {
  live_worker t9 garden s1
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"first"}]}}' \
    '{"type":"user","message":{"content":"x"}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Which branch?"}]}}' \
    >"$HOME/.claude/projects/p/s1.jsonl"
  dispatch last t9
  [ "$status" -eq 0 ]
  [ "$output" = "Which branch?" ]
}

@test "last falls back to the screen" {
  live_worker t9 garden s1
  printf 'line on screen\n' >"$FAKE_DIR/hc-read.txt"
  dispatch last t9
  [ "$output" = "line on screen" ]
}

@test "last of an exited worker reads the session jsonl of its workers line" {
  record_worker t9 garden s1
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Done, see the PR."}]}}' \
    >"$HOME/.claude/projects/p/s1.jsonl"
  dispatch last t9
  [ "$status" -eq 0 ]
  [ "$output" = "Done, see the PR." ]
}

@test "last of a terminal with no workers line says no agent" {
  dispatch last t9
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agent in t9"* ]]
}

@test "remind asks an idle worker for its report again" {
  live_worker t9 garden s1
  set_status t9 idle
  dispatch remind t9 /r.md
  [ "$status" -eq 0 ]
  [ -n "$(calls '^hc send t9 Write the report again to /r.md now, in one Write call.')" ]
}

@test "remind sends nothing to a working worker" {
  live_worker t9 garden s1
  set_status t9 working
  dispatch remind t9 /r.md
  [ "$status" -eq 1 ]
  [ -z "$(calls '^hc send')" ]
}

@test "answer sends the words of the user to an idle worker" {
  live_worker t9 garden s1
  set_status t9 done
  printf 'Use main.\n' >"$BATS_TEST_TMPDIR/a.txt"
  dispatch answer t9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 0 ]
  [ -n "$(calls '^hc send t9 The user answers through the orchestrator:')" ]
  [ -n "$(calls '^Use main\.$')" ]
}

@test "answer sends nothing to a blocked worker" {
  live_worker t9 garden s1
  set_status t9 blocked
  printf 'Use main.\n' >"$BATS_TEST_TMPDIR/a.txt"
  dispatch answer t9 "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 1 ]
  [ -z "$(calls '^hc send')" ]
}

# The Rex versions of the tests above. Each one starts with rsetup.
O=block:01a1ef15-4833-735e-9530-226d79648a16
W=block:01a1ef1f-4f92-7b07-8a51-9be2d9aef276
W2=block:01a1ef1f-4f92-7b07-8a51-9be2d9aef277

rsetup() {
  rex_setup
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$STATE"
}

rex_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-$1-${2:-1}.args"; }

# rex_lost BLOCK BOARD SESSION [PROGRAM]: a worker block after a restart: a shell in the
# place of claude. With PROGRAM, that program runs in front of the shell.
rex_lost() {
  rex_worker "$1" "$2" "$3"
  local f="$FAKE_DIR/rex/process-$1.json"
  cp "$SKILL_DIR/test/fixtures/rex/process-shell.json" "$f"
  if [ -n "${4:-}" ]; then
    jq --arg p "$4" '.foreground.pid = 512 | .foreground.invoked_path = "/usr/bin/" + $p' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  fi
}

@test "workers lists a live worker of the board (Rex)" {
  rsetup
  rex_worker "$W" garden s1
  rex_status "$W" idle
  printf 'RESULT: DONE\n## Result\n' >"$STATE/fix-login-1.md"
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .address <<<"$output")" = "$W" ]
  [ "$(jq -r .name <<<"$output")" = fix-login ]
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ "$(jq -r .mode <<<"$output")" = task ]
  [ "$(jq -r .report_exists <<<"$output")" = true ]
  [ "$(jq -r .first_line <<<"$output")" = "RESULT: DONE" ]
  [ "$(jq -r .waits <<<"$output")" = false ]
}

@test "workers says waits for a blocked worker (Rex)" {
  rsetup
  rex_worker "$W" garden s1
  rex_status "$W" blocked
  dispatch workers garden
  [ "$(jq -r .waits <<<"$output")" = true ]
}

@test "workers skips a stale record (Rex)" {
  rsetup
  record_worker "$W" garden s1
  fake_block session:fake-1 "$W" window:w-1 worker claude
  rex_record_file "$W" '{"board":"lab","role":"worker","session":"s1","rex_session":"session:fake-1"}'
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workers skips a block with another session (Rex)" {
  rsetup
  rex_worker "$W" garden s2
  : >"$STATE/workers"
  record_worker "$W" garden s1
  dispatch workers garden
  [ -z "$output" ]
}

@test "workers skips a worker that a restart replaced with a shell (Rex)" {
  rsetup
  rex_lost "$W" garden s1
  dispatch workers garden
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workers lists a worker that the user started again in its shell (Rex)" {
  rsetup
  rex_lost "$W" garden s1
  cp "$SKILL_DIR/test/fixtures/rex/process-claude.json" "$FAKE_DIR/rex/process-$W.json"
  dispatch workers garden
  [ "$(jq -r .address <<<"$output")" = "$W" ]
}

@test "resumable closes no block of another session (Rex)" {
  rsetup
  rex_lost "$W2" garden s2
  : >"$STATE/workers"
  record_worker "$W" garden s0
  dispatch resumable garden
  [ "$(jq -r .session <<<"$output")" = s0 ]
  [ -z "$(calls 'api call block.close')" ]
}

@test "resume closes the shell that a restart left in the place of the worker (Rex)" {
  rsetup
  rex_orchestrator "$O" garden
  repo_with_push_policy "$BATS_TEST_TMPDIR/repo"
  rex_lost "$W" garden s1
  dispatch resume garden s1
  [ "$status" -eq 0 ]
  close=$(grep -n -m 1 'api call block.close' "$FAKE_LOG" | cut -d: -f1)
  run=$(grep -n -m 1 'window new' "$FAKE_LOG" | cut -d: -f1)
  [ -n "$close" ] && [ -n "$run" ]
  [ "$close" -lt "$run" ]
  [ ! -f "$STATE/rex/$W.json" ]
  [ "$(records | cut -f1)" = "$(sed -n 1p <<<"$output")" ]
  [ "$(records | cut -f1)" != "$W" ]
}

@test "resume-clear drops the record of a worker that a restart replaced with a shell, and closes that shell (Rex)" {
  rsetup
  rex_lost "$W" garden s1
  dispatch resume-clear garden
  [ "$status" -eq 0 ]
  [ -z "$(records)" ]
  [ -n "$(calls 'api call block.close')" ]
  [ ! -f "$STATE/rex/$W.json" ]
}

@test "resumable lists a lost worker shell that runs a program, and does not close it (Rex)" {
  rsetup
  rex_lost "$W" garden s1 vim
  dispatch resumable garden
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ -z "$(calls 'api call block.close')" ]
  [ -f "$STATE/rex/$W.json" ]
}

@test "resumable lists a worker whose block is gone (Rex)" {
  rsetup
  record_worker "$W" garden s1
  dispatch resumable garden
  [ "$status" -eq 0 ]
  [ "$(jq -r .session <<<"$output")" = s1 ]
  [ "$(jq -r .name <<<"$output")" = fix-login ]
  [ "$(jq -r .mode <<<"$output")" = task ]
  [ "$(jq -r .cwd <<<"$output")" = "$BATS_TEST_TMPDIR/repo" ]
}

@test "resumable gives the report fields and done (Rex)" {
  rsetup
  record_worker "$W" garden s1
  printf 'RESULT: DONE\n' >"$STATE/fix-login-1.md"
  dispatch resumable garden
  [ "$(jq -r .report_exists <<<"$output")" = true ]
  [ "$(jq -r .first_line <<<"$output")" = "RESULT: DONE" ]
  [ "$(jq -r .done <<<"$output")" = true ]
}

@test "resumable skips a live worker and another board (Rex)" {
  rsetup
  rex_worker "$W" garden s1
  record_worker "$W2" lab s2
  dispatch resumable garden
  [ -z "$output" ]
}

@test "resume starts with --resume and the cut-turn prompt (Rex)" {
  rsetup
  rex_orchestrator "$O" garden
  repo_with_push_policy "$BATS_TEST_TMPDIR/repo"
  record_worker "$W" garden s1
  dispatch resume garden s1
  [ "$status" -eq 0 ]
  new=$(sed -n 1p <<<"$output")
  [[ "$new" == block:* ]]
  rex_args window-new
  [ "$(arg_after --resume)" = s1 ]
  has_arg BOARD_SESSION=s1
  [ "${RUN_ARGS[-2]}" = -- ]
  [[ "${RUN_ARGS[-1]}" == "The stop of the board orchestrator cut your turn. Continue the task. If you waited for an answer from the user, ask again."* ]]
  [ "$(records | cut -f1)" = "$new" ]
}

@test "resume gives the address of the new orchestrator (Rex)" {
  rsetup
  rex_orchestrator "$O" garden
  repo_with_push_policy "$BATS_TEST_TMPDIR/repo"
  record_worker "$W" garden s1 /r.md
  dispatch resume garden s1
  rex_args window-new
  [[ "${RUN_ARGS[-1]}" == *'dispatch.sh tell "report fix-login /r.md"'* ]]
}

@test "resume exits 1 for an unknown session (Rex)" {
  rsetup
  rex_orchestrator "$O" garden
  dispatch resume garden nope
  [ "$status" -eq 1 ]
  [ -z "$(calls 'window new')" ]
}

@test "resume-clear drops the records that are not live (Rex)" {
  rsetup
  record_worker "$W2" garden s0
  rex_worker "$W" garden s1
  record_worker "$O" lab s2
  dispatch resume-clear garden
  [ "$status" -eq 0 ]
  [ "$(records | cut -f5 | tr '\n' ' ')" = "s1 s2 " ]
}

@test "resume-clear SESSION drops only that record (Rex)" {
  rsetup
  record_worker "$W2" garden s0
  record_worker "$W" garden s3
  dispatch resume-clear garden s0
  [ "$(records | cut -f5)" = s3 ]
}

@test "answer sends nothing to a blocked worker (Rex)" {
  rsetup
  rex_orchestrator "$O" garden
  rex_worker "$W" garden s1
  rex_status "$W" blocked
  printf 'Use main.\n' >"$BATS_TEST_TMPDIR/a.txt"
  dispatch answer "$W" "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 1 ]
  [ -z "$(calls '^rex send ')" ]
}
