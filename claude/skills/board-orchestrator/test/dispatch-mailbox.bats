#!/usr/bin/env bats
# The hand-over to the mailbox of the board service.

bats_require_minimum_version 1.5.0
load helper

O=block:01a1ef15-4833-735e-9530-226d79648a16
W=block:01a1ef1f-4f92-7b07-8a51-9be2d9aef276
P=block:01a1ef2a-0000-7000-8000-000000000001

setup() {
  rex_setup
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$STATE"
  # A Unix socket path has at most about 104 bytes: use a short folder.
  SOCK_DIR=$(mktemp -d /tmp/bm.XXXX)
  export BOARD_SOCKET="$SOCK_DIR/b.sock"
}

teardown() {
  kill_watchers
  [ -z "${SOCK_PID:-}" ] || kill "$SOCK_PID" 2>/dev/null || true
  rm -rf "$SOCK_DIR"
}

dispatch() { run bash "$SKILL_DIR/dispatch.sh" "$@"; }

# fake_socket REPLY: start the fake service socket in the background.
fake_socket() {
  "$SKILL_DIR/test/fake-board-socket" "$BOARD_SOCKET" "$1" &
  SOCK_PID=$!
  local i
  for i in $(seq 50); do [ -S "$BOARD_SOCKET" ] && return 0; sleep 0.1; done
  return 1
}

mailbox() { bash -c 'source "$1/term.sh"; board_mailbox "$2"' _ "$SKILL_DIR" "$1"; }

@test "board_mailbox is true when the service says true" {
  fake_socket '{"v":1,"mailbox":true}'
  run mailbox session:fake-1
  [ "$status" -eq 0 ]
}

@test "board_mailbox is false with mailbox false" {
  fake_socket '{"v":1,"mailbox":false}'
  run mailbox session:fake-1
  [ "$status" -eq 1 ]
}

@test "board_mailbox is false with no socket" {
  run mailbox session:fake-1
  [ "$status" -eq 1 ]
}

@test "board_mailbox is false when the server closes with no line" {
  fake_socket ''
  run mailbox session:fake-1
  [ "$status" -eq 1 ]
}

@test "board_mailbox is false when the server does not answer" {
  fake_socket HANG
  start=$SECONDS
  run mailbox session:fake-1
  [ "$status" -eq 1 ]
  [ $((SECONDS - start)) -lt 3 ]
}

@test "board_socket uses BOARD_SOCKET, then XDG_RUNTIME_DIR, then TMPDIR" {
  run bash -c 'source "$1/term.sh"; board_socket' _ "$SKILL_DIR"
  [ "$output" = "$BOARD_SOCKET" ]
  unset BOARD_SOCKET
  XDG_RUNTIME_DIR=/run/x/ run bash -c 'source "$1/term.sh"; board_socket' _ "$SKILL_DIR"
  [ "$output" = /run/x/board.sock ]
  unset XDG_RUNTIME_DIR
  TMPDIR=/tmp/t/ run bash -c 'source "$1/term.sh"; board_socket' _ "$SKILL_DIR"
  [ "$output" = /tmp/t/board.sock ]
}

# notice_setup: an orchestrator P of garden and a worker W.
notice_setup() {
  fake_block session:fake-1 "$P" window:p-1 orchestrator claude
  rex_record_file "$P" '{"board":"garden","role":"orchestrator","rex_session":"session:fake-1","window":"window:p-1"}'
  printf '%s\tgarden\n' "$P" >"$STATE/orchestrator-garden"
  rex_worker "$W" garden s1
}

@test "notice sends nothing and writes no record when the mailbox runs" {
  notice_setup
  fake_socket '{"v":1,"mailbox":true}'
  dispatch notice "$W" blocked "approve Bash"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(jq -r '.notice // "none"' "$STATE/rex/$W.json")" = none ]
  [ ! -s "$STATE/rex/outbox-session:fake-1.jsonl" ]
}

@test "notice working clears the notice field also when the mailbox runs" {
  notice_setup
  rec="$STATE/rex/$W.json"
  jq '.notice = "blocked"' "$rec" >"$rec.tmp" && mv "$rec.tmp" "$rec"
  fake_socket '{"v":1,"mailbox":true}'
  dispatch notice "$W" working
  [ "$status" -eq 0 ]
  [ "$(jq -r '.notice // "none"' "$rec")" = none ]
}

@test "with the mailbox down, notice works as today" {
  notice_setup
  fake_socket '{"v":1,"mailbox":false}'
  dispatch notice "$W" blocked "approve Bash"
  [ "$status" -eq 0 ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
  [ "$(jq -r .notice "$STATE/rex/$W.json")" = blocked ]
}

@test "deliver sends nothing and removes the quiet files when the mailbox runs" {
  notice_setup
  out="$STATE/rex/outbox-session:fake-1.jsonl"
  jq -cn --arg p "$P" '{to:$p, board:"garden", text:"<rex>x</rex>", at:0}' >"$out"
  : >"$out.quiet-1"
  : >"$out.waits-1"
  before=$(cat "$out")
  fake_socket '{"v":1,"mailbox":true}'
  dispatch deliver session:fake-1
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(cat "$out")" = "$before" ]
  [ ! -e "$out.quiet-1" ]
  [ ! -e "$out.waits-1" ]
}

@test "tell queues for the orchestrator when the mailbox runs and no watcher runs" {
  notice_setup
  fake_socket '{"v":1,"mailbox":true}'
  export REX_SESSION=session:fake-1 REX_BLOCK=$W BOARD=garden BOARD_NAME=fix-login BOARD_ORCHESTRATOR=$P
  dispatch tell "report fix-login /r.md"
  [ "$status" -eq 0 ]
  [ -z "$(calls '^rex send ')" ]
  [ "$(wc -l <"$STATE/rex/outbox-session:fake-1.jsonl")" -eq 1 ]
}
