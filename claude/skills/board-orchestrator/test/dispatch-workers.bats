#!/usr/bin/env bats
# dispatch.sh workers, resumable, resume, resume-clear, close, last, remind, answer.

bats_require_minimum_version 1.5.0
load helper

dispatch() { run bash "$SKILL_DIR/dispatch.sh" "$@"; }
records() { cat "$XDG_STATE_HOME/board-orchestrator-hc/workers"; }

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
