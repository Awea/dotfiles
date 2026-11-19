#!/usr/bin/env bats
# Tests of when-free. A fake probe reads "LOAD CORES MEM_MB" from a file.
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  WF="$BATS_TEST_DIRNAME/../when-free"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  LOCK="$XDG_STATE_HOME/when-free/lock"
  PROBE_FILE="$BATS_TEST_TMPDIR/probe"
  printf '#!/usr/bin/env bash\ncat %q\n' "$PROBE_FILE" >"$BATS_TEST_TMPDIR/probe.sh"
  chmod +x "$BATS_TEST_TMPDIR/probe.sh"
  export WHEN_FREE_PROBE="$BATS_TEST_TMPDIR/probe.sh"
  export WHEN_FREE_POLL=0.2 WHEN_FREE_HOLD=0 WHEN_FREE_LOAD=0.7 WHEN_FREE_MEM_MB=4096
  probe 1.0 20 16000
}

probe() { printf '%s %s %s\n' "$1" "$2" "$3" >"$PROBE_FILE"; }

# wait_for FILE: wait up to 5 s for FILE to exist.
wait_for() {
  for _ in $(seq 50); do
    [ -e "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# wait_grep TEXT FILE: wait up to 5 s for TEXT in FILE.
wait_grep() {
  for _ in $(seq 50); do
    grep -q "$1" "$2" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "runs the command at once when the machine is free" {
  run "$WF" echo hello
  [ "$status" -eq 0 ]
  [ "$output" = hello ]
}

@test "gives the exit code of the command" {
  run "$WF" bash -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "shows the usage and exits 2 with no command" {
  run "$WF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: when-free"* ]]
}

@test "WHEN_FREE=off runs the command with no probe" {
  export WHEN_FREE_PROBE=/nonexistent
  WHEN_FREE=off run "$WF" echo off
  [ "$status" -eq 0 ]
  [ "$output" = off ]
}

@test "waits while the load is high and starts when it drops" {
  probe 18.0 20 16000
  "$WF" touch "$BATS_TEST_TMPDIR/ran" 2>"$BATS_TEST_TMPDIR/err" &
  pid=$!
  wait_grep "waits for the CPU" "$BATS_TEST_TMPDIR/err"
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  probe 2.0 20 16000
  wait_for "$BATS_TEST_TMPDIR/ran"
  wait "$pid"
}

@test "waits while the free RAM is low" {
  probe 1.0 20 1000
  "$WF" touch "$BATS_TEST_TMPDIR/ran" 2>"$BATS_TEST_TMPDIR/err" &
  pid=$!
  wait_grep "waits for RAM" "$BATS_TEST_TMPDIR/err"
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  probe 1.0 20 8000
  wait_for "$BATS_TEST_TMPDIR/ran"
  wait "$pid"
}

@test "the next start waits for the hold of the last start" {
  export WHEN_FREE_HOLD=2
  "$WF" sleep 10 &
  first=$!
  wait_for "$LOCK/pid"
  "$WF" touch "$BATS_TEST_TMPDIR/ran" 2>"$BATS_TEST_TMPDIR/err" &
  second=$!
  wait_grep "waits for another start" "$BATS_TEST_TMPDIR/err"
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  wait_for "$BATS_TEST_TMPDIR/ran"
  wait "$second"
  kill "$first"
}

@test "the hold ends when the command stops" {
  export WHEN_FREE_HOLD=30
  "$WF" true
  run "$WF" echo next
  [ "$status" -eq 0 ]
  [ "$output" = next ]
}

@test "removes a lock whose process is dead" {
  mkdir -p "$LOCK"
  bash -c 'exit 0' &
  dead=$!
  wait "$dead"
  printf '%s\n' "$dead" >"$LOCK/pid"
  run "$WF" echo free
  [ "$status" -eq 0 ]
  [[ "$output" == *free* ]]
}

@test "removes a lock whose pid is now another process" {
  mkdir -p "$LOCK"
  printf '%s\n' "$$" >"$LOCK/pid"
  run "$WF" echo free
  [ "$status" -eq 0 ]
  [[ "$output" == *free* ]]
}

@test "takes a comma in WHEN_FREE_LOAD as a decimal point" {
  export WHEN_FREE_LOAD=0,7
  probe 2.0 20 16000
  run "$WF" echo comma
  [ "$status" -eq 0 ]
  [ "$output" = comma ]
}

@test "a stop during a long poll ends the wait at once" {
  export WHEN_FREE_POLL=10
  probe 18.0 20 16000
  "$WF" true 2>/dev/null &
  pid=$!
  wait_for "$LOCK/pid"
  start=$(date +%s)
  kill -TERM "$pid"
  wait "$pid" || true
  [ $(($(date +%s) - start)) -lt 3 ]
  [ ! -e "$LOCK" ]
}

@test "a stop during the wait removes the lock" {
  probe 18.0 20 16000
  "$WF" true 2>/dev/null &
  pid=$!
  wait_for "$LOCK/pid"
  kill -TERM "$pid"
  wait "$pid" || true
  [ ! -e "$LOCK" ]
}

@test "runs the command with a warning when the probe fails" {
  export WHEN_FREE_PROBE=false
  run "$WF" echo ran
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot read the load"* ]]
  [[ "$output" == *ran* ]]
}
