#!/usr/bin/env bats
# claude-resume.sh, run by the claude-resume mod: record labels each hc terminal that runs
# Claude with its session, resume types claude --resume in a terminal that lost Claude.

load helper

RESUME="$BATS_TEST_DIRNAME/../bin/claude-resume.sh"
ID=1966be76-a987-408d-b5df-f97501074037

# terminal ADDR PID FOREGROUND_PID FOREGROUND_NAME LABELS_JSON [STATE]: a fake hc terminal,
# in hc ls and hc get.
terminal() {
  jq -n --arg a "$1" --argjson pid "$2" --argjson fp "$3" --arg fn "$4" --argjson l "$5" \
    --arg s "${6:-live}" \
    '{address:$a, state:$s, argv:["/usr/bin/zsh"], pid:$pid,
      foreground:{name:$fn, pid:$fp}, labels:$l}' >"$FAKE_DIR/hc-get-$1.json"
  local ls="$FAKE_DIR/hc-ls.json"
  [ -f "$ls" ] || printf '{"terminals":[]}\n' >"$ls"
  jq --arg a "$1" --arg s "${6:-live}" '.terminals += [{address:$a, state:$s}]' "$ls" >"$ls.tmp"
  mv "$ls.tmp" "$ls"
}

# fake_ps: a ps that gives the start time of PID from $FAKE_DIR/ps-start-PID and fails
# when that file is missing. Other calls go to the real ps.
fake_ps() {
  mkdir -p "$HOME/.local/bin"
  cat >"$HOME/.local/bin/ps" <<'EOF'
#!/bin/bash
if [ "$1 $2 $3" = "-o lstart= -p" ]; then
  [ -f "$FAKE_DIR/ps-start-$4" ] || exit 1
  cat "$FAKE_DIR/ps-start-$4"
else
  exec /bin/ps "$@"
fi
EOF
  chmod +x "$HOME/.local/bin/ps"
}

# started PID TIME: the fake start time of PID.
started() {
  printf '%s\n' "$2" >"$FAKE_DIR/ps-start-$1"
}

# labels SESSION CWD PID [EXTRA_JSON]: the labels that record writes.
labels() {
  jq -cn --arg s "$1" --arg c "$2" --arg p "$3" --argjson x "${4:-{\}}" \
    '{"claude.session":$s, "claude.cwd":$c, "claude.pid":$p} + $x'
}

# session_file PID SESSION CWD: the file Claude Code writes for its running process PID.
session_file() {
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  jq -n --argjson p "$1" --arg s "$2" --arg c "$3" '{pid:$p, sessionId:$s, cwd:$c, kind:"interactive"}' \
    >"$CLAUDE_CONFIG_DIR/sessions/$1.json"
}

# fake_board_sh: a board.sh that logs its calls. restart exits 0 for the board "my board"
# in t85, 1 for the board "down" (hc fails), and 3 for any other board.
fake_board_sh() {
  local dir="$HOME/.claude/skills/board-orchestrator"
  mkdir -p "$dir"
  cat >"$dir/board.sh" <<'EOF2'
#!/usr/bin/env bash
printf 'board.sh %s\n' "$*" >>"$FAKE_LOG"
[ "$1|$2|$3" != "restart|my board|t85" ] || exit 0
[ "$2" != down ] || { printf 'board.sh: hc did not start claude in %s\n' "$3" >&2; exit 1; }
printf 'board.sh: %s is not the orchestrator of the board %s\n' "$3" "$2" >&2
exit 3
EOF2
}

setup() {
  hc_setup
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  fake_ps
}

# --- record -------------------------------------------------------------------------

@test "record: a terminal with Claude in the foreground gets the labels of its session" {
  terminal t7v 300 500 claude '{}'
  session_file 500 "$ID" /repo
  started 300 'Sun Nov 15 17:16:05 2026'
  run bash "$RESUME" record
  [ "$status" -eq 0 ]
  [ -n "$(calls "^hc label t7v claude.session=$ID claude.cwd=/repo claude.pid=300 claude.start=Sun Nov 15 17:16:05 2026$")" ]
}

@test "record: a terminal that is Claude itself gets the labels of its session" {
  terminal t7v 500 500 claude '{}'
  session_file 500 "$ID" /repo
  run bash "$RESUME" record
  [ -n "$(calls "^hc label t7v claude.session=$ID claude.cwd=/repo claude.pid=500 claude.start=$")" ]
}

@test "record: labels that are already right get no new label" {
  terminal t7v 300 500 claude "$(labels "$ID" /repo 300 '{"claude.start":"T300"}')"
  session_file 500 "$ID" /repo
  started 300 T300
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: a clear, a new session in the file, writes the new session" {
  terminal t7v 300 500 claude "$(labels "$ID" /repo 300 '{"claude.start":"T300"}')"
  session_file 500 2a1b0c9d-0000-4000-8000-000000000000 /repo
  started 300 T300
  run bash "$RESUME" record
  [ -n "$(calls '^hc label t7v claude.session=2a1b0c9d-0000-4000-8000-000000000000 claude.cwd=/repo ')" ]
}

@test "record: the same session keeps the folder of its label, not the folder of a cd" {
  terminal t7v 300 500 claude "$(labels "$ID" /repo 300)"
  session_file 500 "$ID" /repo/sub
  started 300 T300
  run bash "$RESUME" record
  [ -n "$(calls "^hc label t7v claude.session=$ID claude.cwd=/repo claude.pid=300 claude.start=T300$")" ]
}

@test "record: a program with no Claude session file gets nothing" {
  terminal t7v 300 512 nvim '{}'
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: a session ID that is not a session ID is never written" {
  terminal t7v 300 500 claude '{}'
  session_file 500 '1; rm -rf ~' /repo
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: an idle shell in the same process, after an exit, loses the labels" {
  terminal t7v 300 300 zsh "$(labels "$ID" /repo 300 '{"claude.start":"T300"}')"
  started 300 T300
  run bash "$RESUME" record
  [ -n "$(calls '^hc label t7v claude.session= claude.cwd= claude.pid= claude.start=$')" ]
}

@test "record: a new shell, after a restart, keeps the labels for resume" {
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300)"
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: a new shell with the pid of the old one keeps the labels for resume" {
  terminal t7v 300 300 zsh "$(labels "$ID" /repo 300 '{"claude.start":"T-old"}')"
  started 300 T-new
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: an old session file of a pid that another program has now gets nothing" {
  # Claude keeps the file after a crash or a power loss, and a pid can come back.
  terminal t7v 300 512 nvim '{}'
  session_file 512 "$ID" /repo
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: a board worker gets nothing, the board orchestrator resumes it" {
  terminal t85 300 500 claude '{"board":"shop","board.role":"worker"}'
  session_file 500 "$ID" /repo
  run bash "$RESUME" record
  [ -z "$(calls '^hc label')" ]
}

@test "record: a board orchestrator gets the labels of its session" {
  terminal t85 300 500 claude '{"board":"shop","board.role":"orchestrator"}'
  session_file 500 "$ID" /vault
  run bash "$RESUME" record
  [ -n "$(calls "^hc label t85 claude.session=$ID claude.cwd=/vault claude.pid=300 ")" ]
}

@test "record: a failed hc ls exits 1 with the reason" {
  export FAKE_HC_FAIL=1
  run bash "$RESUME" record
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude-resume"* ]]
}

@test "claude-resume.sh with no command exits 2 with the usage" {
  run bash "$RESUME"
  [ "$status" -eq 2 ]
  [[ "$output" == *"record"* && "$output" == *"resume"* && "$output" == *"tick"* ]]
}

# --- tick -------------------------------------------------------------------------

@test "tick: a shell that lost Claude gets claude --resume and keeps its labels" {
  # The shell is still idle just after the send: record must not see an exit there.
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300)"
  run bash "$RESUME" tick
  [ "$status" -eq 0 ]
  [ -n "$(calls "^hc send t7v cd '/repo' && claude --resume $ID$")" ]
  [ -z "$(calls '^hc label t7v claude.session=')" ]
}

@test "tick: a terminal with Claude in the foreground gets its labels" {
  terminal t7v 300 500 claude '{}'
  session_file 500 "$ID" /repo
  run bash "$RESUME" tick
  [ -n "$(calls "^hc label t7v claude.session=$ID claude.cwd=/repo claude.pid=300 ")" ]
  [ -z "$(calls '^hc send')" ]
}

# --- resume -------------------------------------------------------------------------

@test "resume: a shell that replaced Claude after a restart gets claude --resume" {
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300)"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [ -n "$(calls "^hc label t7v claude.pid=400 claude.start=$")" ]
  [ -n "$(calls "^hc send t7v cd '/repo' && claude --resume $ID$")" ]
}

@test "resume: a new shell with the pid of the old one, after a reboot, gets claude --resume" {
  fake_ps
  started 300 'Sun Nov 15 17:16:05 2026'
  terminal t7v 300 300 zsh "$(labels "$ID" /repo 300 '{"claude.start":"Fri Nov 13 09:59:11 2026"}')"
  run bash "$RESUME" resume
  [ -n "$(calls "^hc label t7v claude.pid=300 claude.start=Sun Nov 15 17:16:05 2026$")" ]
  [ -n "$(calls "^hc send t7v cd '/repo' && claude --resume $ID$")" ]
}

@test "resume: the same pid and start time gets nothing" {
  fake_ps
  started 300 'Sun Nov 15 17:16:05 2026'
  terminal t7v 300 300 zsh "$(labels "$ID" /repo 300 '{"claude.start":"Sun Nov 15 17:16:05 2026"}')"
  run bash "$RESUME" resume
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "resume: a failed send puts the old labels back and goes on with the next terminal" {
  export FAKE_SEND_FAIL=1
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300 '{"claude.start":"old"}')"
  terminal t6d 401 401 zsh "$(labels 1a293b50-25b0-455d-9072-bf8ac959159c /other 301)"
  run bash "$RESUME" resume
  [ "$status" -eq 1 ]
  [ -n "$(calls '^hc label t7v claude.pid=300 claude.start=old$')" ]
  [ -n "$(calls '^hc send t6d ')" ]
}

@test "resume: an empty folder label does not move the other labels" {
  terminal t7v 400 400 zsh "$(labels "$ID" '' 300)"
  run bash "$RESUME" resume
  [ -n "$(calls '^hc label t7v claude.pid=400 ')" ]
  [ -n "$(calls "^hc send t7v cd '.' && claude --resume $ID$")" ]
}

@test "resume: a folder with a quote stays one word in bash 4.2 and older too" {
  terminal t7v 400 400 zsh "$(labels "$ID" "/repo/it's" 300)"
  BASH_COMPAT=42 run bash "$RESUME" resume
  [ -n "$(calls "^hc send t7v cd '/repo/it'\\\\''s' && claude --resume $ID$")" ]
}

@test "resume: the pid label changes before the send, so a second run types nothing" {
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300)"
  run bash "$RESUME" resume
  [ "$(grep -n -E '^hc (label|send) t7v' "$FAKE_LOG" | cut -d' ' -f2 | tr '\n' ' ')" = "label send " ]
}

@test "resume: the same program as when Claude started gets nothing" {
  terminal t7v 300 300 zsh "$(labels "$ID" /repo 300)"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "resume: a shell that runs another program gets nothing" {
  terminal t7v 400 512 nvim "$(labels "$ID" /repo 300)"
  run bash "$RESUME" resume
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "resume: a board worker gets nothing, the board orchestrator resumes it" {
  terminal t85 400 400 zsh "$(labels "$ID" /repo 300 '{"board":"shop","board.role":"worker"}')"
  run bash "$RESUME" resume
  [ -z "$(calls '^hc (send|label)')" ]
}

@test "resume: a board orchestrator shell after a restart starts the orchestrator again" {
  fake_board_sh
  terminal t85 400 400 zsh "$(labels "$ID" /vault 300 '{"board":"my board","board.role":"orchestrator"}')"
  run bash "$RESUME" resume
  [ "$status" -eq 0 ]
  label=$(grep -n -m 1 "^hc label t85 claude.pid=400 claude.start=$" "$FAKE_LOG" | cut -d: -f1)
  restart=$(grep -n -m 1 "^board.sh restart my board t85$" "$FAKE_LOG" | cut -d: -f1)
  [ -n "$label" ] && [ -n "$restart" ]
  [ "$label" -lt "$restart" ]
  [ -z "$(calls '^hc send')" ]
}

@test "resume: an orchestrator that board.sh refuses gets nothing, and no new try" {
  fake_board_sh
  terminal t85 400 400 zsh "$(labels "$ID" /vault 300 '{"board":"lab","board.role":"orchestrator"}')"
  run bash "$RESUME" resume
  [ "$status" -eq 1 ]
  [[ "$output" == *"t85 is not the orchestrator of the board lab"* ]]
  [ -z "$(calls '^hc send')" ]
  [ -z "$(calls "^hc label t85 claude.pid=300 ")" ]
}

@test "resume: an orchestrator that board.sh could not start gets its old labels back" {
  fake_board_sh
  terminal t85 400 400 zsh "$(labels "$ID" /vault 300 '{"board":"down","board.role":"orchestrator"}')"
  run bash "$RESUME" resume
  [ "$status" -eq 1 ]
  [ -n "$(calls "^hc label t85 claude.pid=300 claude.start=$")" ]
}

@test "resume: a finished terminal gets nothing" {
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300)" finished
  run bash "$RESUME" resume
  [ -z "$(calls '^hc (get|send|label)')" ]
}

@test "resume: a session label that is not a session ID is never typed" {
  terminal t7v 400 400 zsh "$(labels '1; rm -rf ~' /repo 300)"
  run bash "$RESUME" resume
  [ -z "$(calls '^hc send')" ]
}

@test "resume: a folder with a quote stays one word" {
  terminal t7v 400 400 zsh "$(labels "$ID" "/repo/it's" 300)"
  run bash "$RESUME" resume
  [ -n "$(calls "^hc send t7v cd '/repo/it'\\\\''s' && claude --resume $ID$")" ]
}

@test "resume: each terminal that lost Claude gets its own session" {
  terminal t7v 400 400 zsh "$(labels "$ID" /repo 300)"
  terminal t6d 401 401 zsh "$(labels 1a293b50-25b0-455d-9072-bf8ac959159c /other 301)"
  run bash "$RESUME" resume
  [ -n "$(calls "^hc send t7v cd '/repo' && claude --resume $ID$")" ]
  [ -n "$(calls "^hc send t6d cd '/other' && claude --resume 1a293b50-25b0-455d-9072-bf8ac959159c$")" ]
}

@test "resume: a failed hc ls exits 1 with the reason" {
  export FAKE_HC_FAIL=1
  run bash "$RESUME" resume
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude-resume"* ]]
}
