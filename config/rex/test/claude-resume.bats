#!/usr/bin/env bats
# claude-resume.sh under Rex: record keeps the Claude session of each pane, resume starts
# Claude again in a pane with a new idle shell. A board orchestrator gets board.sh restart;
# a worker gets nothing.

load helper

RESUME="$BATS_TEST_DIRNAME/../bin/claude-resume.sh"
ID=1966be76-a987-408d-b5df-f97501074037
B1=block:00000000-0000-0000-0000-000000000001
B2=block:00000000-0000-0000-0000-000000000002

setup() {
  rex_setup
  export BOARD_SH="$BATS_TEST_TMPDIR/board.sh"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  STATE_FILE="$XDG_STATE_HOME/rex/claude-resume.json"
  # restart exits 0 for the board "home", 3 for "other", 1 for "down".
  cat >"$BOARD_SH" <<'SH'
#!/usr/bin/env bash
printf 'board.sh %s\n' "$*" >>"$FAKE_LOG"
case "$2" in
  home) exit 0 ;;
  other) echo "board.sh: $3 is not the orchestrator of the board $2" >&2; exit 3 ;;
  *) echo "board.sh: rex did not answer" >&2; exit 1 ;;
esac
SH
}

# pane BLOCK shell|claude: a live block. The shell pid is 929020, the Claude pid 917026.
pane() { fake_block session:s1 "$1" window:w1 "pane-$1" "$2"; }

# claude_file: the file that Claude Code keeps for the claude process of the fake pane.
claude_file() {
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  jq -n --arg s "$ID" '{pid:917026, sessionId:$s, cwd:"/tmp", kind:"interactive"}' >"$CLAUDE_CONFIG_DIR/sessions/917026.json"
}

# board_record BLOCK BOARD ROLE: the board record of a block.
board_record() { rex_record_file "$1" "$(jq -cn --arg b "$2" --arg r "$3" '{board:$b, role:$r}')"; }

# state JSON: the state file of claude-resume.
state() { mkdir -p "$(dirname "$STATE_FILE")"; printf '%s\n' "$1" >"$STATE_FILE"; }

# state_of BLOCK: the state of a block, as compact JSON.
state_of() { jq -c --arg b "$1" '.[$b] // null' "$STATE_FILE"; }

@test "record skips a worker block" {
  pane $B1 claude
  claude_file
  board_record $B1 home worker
  run bash "$RESUME" record
  [ "$status" -eq 0 ]
  [ "$(state_of $B1)" = null ]
}

@test "record keeps board, pid and start of an orchestrator while Claude runs" {
  pane $B1 claude
  board_record $B1 home orchestrator
  run bash "$RESUME" record
  [ "$status" -eq 0 ]
  [ "$(state_of $B1 | jq -r '[.board, .pid, has("claude")] | join(" ")')" = "home 917026 false" ]
}

@test "record skips a board block with an unknown role" {
  pane $B1 claude
  claude_file
  board_record $B1 home boss
  run bash "$RESUME" record
  [ "$status" -eq 0 ]
  [ "$(state_of $B1)" = null ]
}

@test "resume does not type claude --resume in a worker block" {
  pane $B1 shell
  board_record $B1 home worker
  state "{\"$B1\":{\"claude\":\"$ID\",\"cwd\":\"/tmp\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [ -z "$(calls 'board.sh')" ]
  [ -z "$(calls 'rex send')" ]
}

@test "resume does nothing in a board block with an unknown role" {
  pane $B1 shell
  board_record $B1 home boss
  state "{\"$B1\":{\"board\":\"home\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [ -z "$(calls 'board.sh')" ]
  [ -z "$(calls 'rex send')" ]
}

@test "resume runs board.sh restart for an orchestrator with a new idle shell" {
  pane $B1 shell
  board_record $B1 home orchestrator
  state "{\"$B1\":{\"board\":\"home\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [[ "$output" == *"orchestrator of home"* ]]
  [ "$(calls 'board.sh')" = "board.sh restart home $B1" ]
  [ -z "$(calls 'rex send')" ]
  [ "$(state_of $B1 | jq -r .pid)" = 929020 ]
}

@test "resume does not restart an orchestrator in the same shell" {
  pane $B1 shell
  board_record $B1 home orchestrator
  state "{\"$B1\":{\"board\":\"home\",\"pid\":\"929020\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [ -z "$(calls 'board.sh')" ]
}

@test "resume does not restart an orchestrator while Claude runs" {
  pane $B1 claude
  # The shell is the child, Claude is in the foreground.
  jq -c '.child.pid = 929020' "$FAKE_DIR/rex/process-$B1.json" >"$FAKE_DIR/p" && mv "$FAKE_DIR/p" "$FAKE_DIR/rex/process-$B1.json"
  board_record $B1 home orchestrator
  state "{\"$B1\":{\"board\":\"home\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [ -z "$(calls 'board.sh')" ]
}

@test "an exit 3 is not tried again" {
  pane $B1 shell
  board_record $B1 other orchestrator
  state "{\"$B1\":{\"board\":\"other\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not the orchestrator of the board other"* ]]
  [ "$(state_of $B1 | jq -r .pid)" = 929020 ]
  run bash "$RESUME" resume
  [ "$(calls 'board.sh' | wc -l)" -eq 1 ]
}

@test "another failure of restart is tried again at the next tick" {
  pane $B1 shell
  board_record $B1 down orchestrator
  state "{\"$B1\":{\"board\":\"down\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 1 ]
  [[ "$output" == *"rex did not answer"* ]]
  [ "$(state_of $B1 | jq -r .pid)" = 111 ]
  run bash "$RESUME" resume
  [ "$(calls 'board.sh' | wc -l)" -eq 2 ]
}

@test "a plain Claude pane still resumes as before" {
  pane $B2 shell
  state "{\"$B2\":{\"claude\":\"$ID\",\"cwd\":\"/tmp/my dir\",\"pid\":\"111\",\"start\":\"\"}}"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ID"* ]]
  [ -z "$(calls 'board.sh')" ]
  mapfile -d '' args <"$FAKE_DIR/rex/rex-send-1.args"
  [[ "${args[*]}" == *"cd '/tmp/my dir' && claude --resume $ID"* ]]
}
