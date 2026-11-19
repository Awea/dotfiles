#!/usr/bin/env bats
# board-open.sh and board-stop.sh, the Renux popups of the board orchestrator. A fake
# board.sh logs its arguments and REX_CLIENT.

load helper

setup() {
  hc_setup
  export BOARD_SH="$BATS_TEST_TMPDIR/board.sh"
  cat >"$BOARD_SH" <<'SH'
#!/usr/bin/env bash
echo "board.sh $* client=${REX_CLIENT-} shown=$(grep -cE '(Opening|Stopping) ' "${POPUP_OUT-/dev/null}")" >>"$FAKE_LOG"
echo "term=${BOARD_TERM-} for $1" >>"$FAKE_LOG"
case $1 in
  boards) echo '[{"key":"a","board":"alpha"},{"key":"b","board":"beta"}]' ;;
  running) printf '%s\n' "${FAKE_RUNNING:-[\"alpha\",\"beta\"]}" ;;
  open | stop)
    if [[ -n ${FAKE_FAIL-} ]]; then printf '%s\nsecond line\n' "$FAKE_FAIL" >&2; exit 1; fi ;;
esac
SH
  chmod +x "$BOARD_SH"
}

# popup SCRIPT KEYS: run the popup with KEYS on stdin.
popup() {
  local script=$1 keys=$2
  export POPUP_OUT="$BATS_TEST_TMPDIR/popup.out"
  run bash -c 'printf "%b" "$2" | bash "$1" /tmp sess blk cli1 >"$3" 2>&1' _ "$BIN/$script" "$keys" "$POPUP_OUT"
  output=$(<"$POPUP_OUT")
}

@test "board-open lists the boards with their keys" {
  popup board-open.sh '\e'
  [ "$status" -eq 0 ]
  [[ $output == *"Open a board orchestrator"* ]]
  [[ $output == *"[a] alpha"* ]]
  [[ $output == *"[b] beta"* ]]
}

@test "a key opens that board with the client of the popup" {
  popup board-open.sh 'zb'
  [ "$status" -eq 0 ]
  [[ $output == *"Opening beta…"* ]]
  [ -n "$(calls 'board.sh open beta client=cli1')" ]
}

@test "the popup shows Opening before board.sh open runs" {
  popup board-open.sh 'a'
  [ -n "$(calls 'board.sh open alpha .* shown=1$')" ]
}

@test "Escape opens nothing" {
  popup board-open.sh '\e'
  [ "$status" -eq 0 ]
  [ -z "$(calls 'board.sh open')" ]
}

@test "a failed open shows the error" {
  export FAKE_FAIL="no such board"
  popup board-open.sh 'ax'
  [ "$status" -eq 1 ]
  [[ $output == *"no such board"* ]]
  [[ $output != *"second line"* ]]
}

@test "board-stop stops the picked board" {
  popup board-stop.sh '2'
  [ "$status" -eq 0 ]
  [ -n "$(calls 'board.sh stop beta .* shown=1$')" ]
  [[ $output == *"Stop a board orchestrator"* ]]
  [[ $output == *"[1] alpha"* ]]
  [[ $output == *"Stopping beta…"* ]]
  [ -n "$(calls 'board.sh stop beta client=cli1')" ]
}

@test "board-stop with no running board says so" {
  export FAKE_RUNNING='[]'
  popup board-stop.sh 'x'
  [ "$status" -eq 0 ]
  [[ $output == *"No board orchestrator runs."* ]]
  [ -z "$(calls 'board.sh stop')" ]
}

@test "board-stop with one running board stops it with no key" {
  export FAKE_RUNNING='["alpha"]'
  popup board-stop.sh ''
  [ "$status" -eq 0 ]
  [[ $output == *"Stopping alpha…"* ]]
  [ -n "$(calls 'board.sh stop alpha client=cli1 shown=1')" ]
}

@test "the popups run board.sh for Renux, with no env" {
  popup board-stop.sh '1'
  [ "$status" -eq 0 ]
  [ -n "$(calls '^term=rex for running$')" ]
  [ -n "$(calls '^term=rex for stop$')" ]
}

@test "Escape in board-stop stops nothing" {
  popup board-stop.sh '\e'
  [ "$status" -eq 0 ]
  [[ $output == *"[2] beta"* ]]
  [ -z "$(calls 'board.sh stop')" ]
}

@test "a failed stop shows its first line and exits 1 after a key" {
  export FAKE_FAIL="cannot stop"
  popup board-stop.sh '1x'
  [ "$status" -eq 1 ]
  [[ $output == *"cannot stop"* ]]
  [[ $output != *"second line"* ]]
}

@test "a bad list shows an error, not an empty list" {
  export FAKE_RUNNING='not json'
  popup board-stop.sh 'x'
  [ "$status" -eq 1 ]
  [[ $output == *"jq"* || $output == *"parse"* ]]
  [[ $output != *"No board orchestrator runs."* ]]
}
