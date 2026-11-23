#!/usr/bin/env bats
# Tests of rex-pane, with the fake rex of the board-orchestrator tests. The fixture
# view-split.json has two tabs: the worker block 1 on the left half of its tab, block 2
# at the top right and block 3 at the bottom right. Block 4 is alone in another tab.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031,SC2154 # stderr comes from run --separate-stderr. Each test sets its own env: bats runs each test in a subshell.

bats_require_minimum_version 1.5.0

block() { printf 'block:00000000-0000-0000-0000-%012d\n' "$1"; }

setup() {
  RP="$BATS_TEST_DIRNAME/../rex-pane"
  ORCH="$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test"
  export REX_BIN="$ORCH/fake-rex"
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake" FAKE_LOG="$BATS_TEST_TMPDIR/log"
  mkdir -p "$FAKE_DIR/rex"
  : >"$FAKE_LOG"
  export REX_SESSION=session:fake-1 REX_BLOCK
  REX_BLOCK=$(block 1)
  local i w
  for i in 1 2 3 4; do
    w=window:fake-1
    [ "$i" != 4 ] || w=window:fake-2
    jq -cn --arg b "$(block "$i")" --arg w "$w" \
      '{session_id: "session:fake-1", window_id: $w, window_label: "tab", block_id: $b}' \
      >>"$FAKE_DIR/rex/blocks.jsonl"
  done
  cp "$ORCH/fixtures/rex/view-split.json" "$FAKE_DIR/rex/view.json"
  cp "$ORCH/fixtures/rex/process-shell.json" "$FAKE_DIR/rex/process-$(block 2).json"
  printf '{"title":"gpg"}\n' >"$FAKE_DIR/rex/title-$(block 2).json"
  printf '{"title":"logs"}\n' >"$FAKE_DIR/rex/title-$(block 3).json"
}

# set_rect BLOCK X Y W H: move the leaf of BLOCK in the view to that rect.
set_rect() {
  local f="$FAKE_DIR/rex/view.json"
  jq --arg b "$(block "$1")" --argjson r "[$2,$3,$4,$5]" \
    '(.. | objects | select(.block_id? == $b and has("rect")) | .rect) = $r' "$f" >"$f.tmp"
  mv "$f.tmp" "$f"
}

@test "ls lists the other panes of the tab with their position" {
  run "$RP" ls
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$(printf '00000002\tright\tzsh\tgpg')" ]
  [ "${lines[1]}" = "$(printf '00000003\tright\tclaude\tlogs')" ]
}

@test "ls does not list the worker pane nor a pane of another tab" {
  run "$RP" ls
  [ "$status" -eq 0 ]
  [[ "$output" != *00000001* ]]
  [[ "$output" != *00000004* ]]
}

@test "a pane on a diagonal has two position words" {
  set_rect 1 0 0 0.5 0.5
  run "$RP" ls
  [ "$status" -eq 0 ]
  [ "$(cut -f1,2 <<<"$output")" = "$(printf '00000002\tright\n00000003\tbelow right')" ]
}

@test "ls with no other pane prints nothing and exits 0" {
  export REX_BLOCK
  REX_BLOCK=$(block 4)
  run --separate-stderr "$RP" ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"rex-pane: no other pane in this tab"* ]]
}

@test "ls exits 1 when REX_BLOCK is not in the view" {
  export REX_BLOCK
  REX_BLOCK=$(block 9)
  run "$RP" ls
  [ "$status" -eq 1 ]
  [[ "$output" == *"rex-pane: no tab for $REX_BLOCK"* ]]
}

@test "ls exits 1 outside Renux" {
  unset REX_BLOCK
  run "$RP" ls
  [ "$status" -eq 1 ]
  [[ "$output" == *"rex-pane: not in Renux"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "ls exits 1 when Rex fails" {
  export FAKE_REX_FAIL=1
  run "$RP" ls
  [ "$status" -eq 1 ]
  [[ "$output" == *"rex-pane: "* ]]
}

@test "an unknown command is a usage error" {
  run "$RP" split
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: rex-pane"* ]]
  [ ! -s "$FAKE_LOG" ]
}

# sent_args: the arguments of the first rex send, one on each line.
sent_args() { tr '\0' '\n' <"$FAKE_DIR/rex/rex-send-1.args"; }

@test "read prints the end of the pane" {
  seq 1 50 | sed 's/^/line /' >"$FAKE_DIR/rex/capture.txt"
  run "$RP" read 00000002 5
  [ "$status" -eq 0 ]
  [ "$output" = "$(seq 46 50 | sed 's/^/line /')" ]
  grep -qxF "rex capture -s $REX_SESSION -b $(block 2) --trim" "$FAKE_LOG"
}

@test "read gives 40 lines by default" {
  seq 1 50 >"$FAKE_DIR/rex/capture.txt"
  run "$RP" read 00000003
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 40 ]
  [ "${lines[0]}" = 11 ]
}

@test "read with a bad number of lines is a usage error" {
  local n
  for n in 0 -3 x 4x; do
    run "$RP" read 00000002 "$n"
    [ "$status" -eq 2 ]
  done
  [ ! -s "$FAKE_LOG" ]
}

@test "a full block ID of the tab is a pane" {
  printf 'hello\n' >"$FAKE_DIR/rex/capture.txt"
  run "$RP" read "$(block 2)"
  [ "$status" -eq 0 ]
  [ "$output" = hello ]
}

@test "a position word with two matches exits 3" {
  run "$RP" read right
  [ "$status" -eq 3 ]
  [[ "$output" == *"rex-pane ls"* ]]
  run ! grep -q 'rex capture' "$FAKE_LOG"
}

@test "a position word with no match exits 3" {
  run "$RP" read left
  [ "$status" -eq 3 ]
  [[ "$output" == *"rex-pane ls"* ]]
}

@test "a position word picks the one pane on that side" {
  set_rect 1 0 0 0.5 0.5
  printf 'bottom\n' >"$FAKE_DIR/rex/capture.txt"
  run "$RP" read below
  [ "$status" -eq 0 ]
  grep -qxF "rex capture -s $REX_SESSION -b $(block 3) --trim" "$FAKE_LOG"
}

@test "a pane of another tab exits 3" {
  run "$RP" read 00000004
  [ "$status" -eq 3 ]
  run "$RP" type "$(block 4)" ls
  [ "$status" -eq 3 ]
  run ! grep -q 'rex capture\|rex send' "$FAKE_LOG"
}

@test "the own pane exits 3" {
  run "$RP" read 00000001
  [ "$status" -eq 3 ]
  run "$RP" type "$REX_BLOCK" ls
  [ "$status" -eq 3 ]
  run ! grep -q 'rex capture\|rex send' "$FAKE_LOG"
}

@test "type sends the text with no Enter" {
  run --separate-stderr "$RP" type 00000002 'gpg-unlock --all'
  [ "$status" -eq 0 ]
  [ "$(sent_args)" = "$(printf '%s\n' -s "$REX_SESSION" -b "$(block 2)" 'gpg-unlock --all')" ]
  [[ "$stderr" == *"rex-pane: typed in 00000002, press Enter there"* ]]
  run ! grep -q 'send-key' "$FAKE_LOG"
}

@test "type refuses a control char" {
  local t
  for t in $'gpg-unlock\n' $'a\rb' $'a\tb' $'\e[201~' $'a\x7fb' $'a\x03'; do
    run "$RP" type 00000002 "$t"
    [ "$status" -eq 2 ]
    [[ "$output" == *"rex-pane: "* ]]
  done
  [ ! -s "$FAKE_LOG" ]
}

@test "type refuses an empty text" {
  run "$RP" type 00000002 ""
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "type exits 1 when Rex fails" {
  export FAKE_REX_SEND_FAIL=1
  run "$RP" type 00000002 gpg-unlock
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing went in"* ]]
}

@test "type refuses a C1 control char and a text that is not UTF-8" {
  local t
  for t in $'a\xc2\x9bXb' $'a\x9bb' $'a\xc2\x85b'; do
    run "$RP" type 00000002 "$t"
    [ "$status" -eq 2 ]
  done
  [ ! -s "$FAKE_LOG" ]
}

@test "type sends UTF-8 text" {
  run "$RP" type 00000002 'echo café œuvre'
  [ "$status" -eq 0 ]
  [ "$(sent_args | tail -1)" = 'echo café œuvre' ]
}

@test "type refuses a pane that is not at a shell prompt" {
  run "$RP" type 00000003 gpg-unlock
  [ "$status" -eq 3 ]
  [[ "$output" == *"rex-pane: 00000003 is not at a shell prompt"* ]]
  jq '.foreground = (.foreground + {pid: 4242, name: "lazygit", path: "/usr/bin/lazygit"})' \
    "$ORCH/fixtures/rex/process-shell.json" >"$FAKE_DIR/rex/process-$(block 2).json"
  run "$RP" type 00000002 P
  [ "$status" -eq 3 ]
  run ! grep -q 'rex send' "$FAKE_LOG"
}

@test "type gives rex send no input but the text" {
  export FAKE_REX_SEND_STDIN=1
  run bash -c 'printf "x\n" | "$1" type 00000002 ls' _ "$RP"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_DIR/rex/send-stdin" ]
}

@test "two panes with the same short ID ask for the full block ID" {
  local f="$FAKE_DIR/rex/view.json"
  jq --arg b "$(block 3)" '(.. | objects | select(.block_id? == $b) | .block_id) = "block:11111111-0000-0000-0000-000000000002"' \
    "$f" >"$f.tmp"
  mv "$f.tmp" "$f"
  run "$RP" read 00000002
  [ "$status" -eq 3 ]
  [[ "$output" == *"full block ID"* ]]
}
