#!/usr/bin/env bats

load helper

setup() {
  rex_setup
  O=block:01a1ef15-4833-735e-9530-226d79648a16
  W=block:01a1ef1f-4f92-7b07-8a51-9be2d9aef276
  rex_orchestrator "$O" "my board"
  rex_worker "$W" "my board" fix-login-1
}

# rex_args CMD [N]: the arguments of the Nth saved call, one for each element of RUN_ARGS.
rex_args() { mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-$1-${2:-1}.args"; }

@test "rex_get maps a Claude block to the hc shape" {
  source "$SKILL_DIR/lib.sh"
  run rex_get "$W"
  [ "$status" -eq 0 ]
  jq -e '.state == "live" and .foreground.name == "claude" and .status.state == "working"
    and .labels["board.role"] == "worker" and .labels.board == "my board"
    and .labels["board.session"] == "fix-login-1" and (.pid | type) == "number"
    and (.argv | length) == 1' <<<"$output"
}

@test "rex_get takes the 8-hex suffix" {
  source "$SKILL_DIR/lib.sh"
  run rex_get "${W: -8}"
  [ "$status" -eq 0 ]
  jq -e '.labels["board.role"] == "worker"' <<<"$output"
}

@test "rex_get shows a blocked status" {
  source "$SKILL_DIR/lib.sh"
  rex_status "$W" blocked "approve Bash: ls"
  run rex_get "$W"
  jq -e '.status.state == "blocked"' <<<"$output"
}

@test "rex_get of a closed block exits 1" {
  source "$SKILL_DIR/lib.sh"
  run rex_get block:00000000-0000-0000-0000-00000000dead
  [ "$status" -eq 1 ]
  "${REX[@]}" api call block.close "{\"session_id\":\"session:fake-1\",\"block_id\":\"$W\"}" >/dev/null
  run rex_get "$W"
  [ "$status" -eq 1 ]
}

@test "rex_get after a restart: the shell is in front, so the worker is lost" {
  source "$SKILL_DIR/lib.sh"
  cp "$SKILL_DIR/test/fixtures/rex/process-shell.json" "$FAKE_DIR/rex/process-$W.json"
  run rex_get "$W"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.foreground.name' <<<"$output")" != claude ]
  # The lost test of worker_terminal: a program in argv that is not env, direnv or claude.
  jq -e '((.argv[0] | split("/") | last) as $p
    | $p != "" and ($p | IN("env", "direnv", "claude") | not)
      and .foreground.name != "claude")' <<<"$output"
}

@test "rex_send sends the text, then Enter" {
  source "$SKILL_DIR/lib.sh"
  rex_send "$W" 'a "b" $c'
  [ -n "$(calls "^rex send -s session:fake-1 -b $W")" ]
  rex_args send
  [ "${RUN_ARGS[4]}" = 'a "b" $c' ]
  [ "$(calls '^rex send -s' | wc -l | tr -d ' ')" = 1 ]
  [ -n "$(calls "^rex send-key -s session:fake-1 -b $W enter")" ]
  # The text goes before the key.
  [ "$(grep -n '^rex send ' "$FAKE_LOG" | cut -d: -f1)" -lt "$(grep -n '^rex send-key' "$FAKE_LOG" | cut -d: -f1)" ]
}

@test "rex_send sends a text with a newline as one bracketed paste" {
  source "$SKILL_DIR/lib.sh"
  rex_send "$W" 'a "b" $c'$'\n''</rex>'
  rex_args send
  [ "${RUN_ARGS[4]}" = $'\e[200~''a "b" $c'$'\n''</rex>'$'\e[201~' ]
  [ "$(calls '^rex send -s' | wc -l | tr -d ' ')" = 1 ]
  [ -n "$(calls "^rex send-key -s session:fake-1 -b $W enter")" ]
}

@test "rex_message from an hc orchestrator names the board of its labels" {
  source "$SKILL_DIR/lib.sh"
  export HC_TERMINAL_ID=t3
  fake_terminal t3 "my board" orchestrator
  rex_message "$W" hi
  rex_args send
  [ "${RUN_ARGS[4]}" = '<rex from="t3 my-board-orchestrator">hi</rex>' ]
}

@test "lib.sh never starts a Rex server" {
  source "$SKILL_DIR/lib.sh"
  [ "${REX[1]}" = --autostart=false ]
}

@test "rex_full resolves a short ID from the workers file when the record and the block are gone" {
  source "$SKILL_DIR/lib.sh"
  rm "$XDG_STATE_HOME/board-orchestrator-hc/rex/$W.json"
  grep -v -F "\"block_id\":\"$W\"" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp"
  mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"
  [ "$(rex_full "${W: -8}")" = "$W" ]
  run rex_full deadbeef
  [ "$status" -eq 1 ]
}

@test "rex_message wraps the text in a rex tag with the sender" {
  source "$SKILL_DIR/lib.sh"
  rex_message "$W" "card 12"
  rex_args send
  [ "${RUN_ARGS[4]}" = "<rex from=\"${O: -8} my-board-orchestrator\">card 12</rex>" ]
  BOARD="my board" BOARD_NAME=worker-x rex_message "$W" hi
  rex_args send 2
  [ "${RUN_ARGS[4]}" = "<rex from=\"${O: -8} worker-x\">hi</rex>" ]
}

@test "rex_wait gives status when the worker is idle" {
  source "$SKILL_DIR/lib.sh"
  rex_status "$W" idle
  [ "$(rex_wait "$W" 30)" = status ]
}

@test "rex_wait gives exit when the block closes" {
  source "$SKILL_DIR/lib.sh"
  printf '#!/usr/bin/env bash\ngrep -v -F "%s" "$FAKE_DIR/rex/blocks.jsonl" >"$FAKE_DIR/rex/b.tmp"; mv "$FAKE_DIR/rex/b.tmp" "$FAKE_DIR/rex/blocks.jsonl"\n' "$W" >"$FAKE_DIR/rex/on-api"
  chmod +x "$FAKE_DIR/rex/on-api"
  [ "$(rex_wait "$W" 30)" = exit ]
}

@test "rex_wait gives timeout when the worker stays working" {
  source "$SKILL_DIR/lib.sh"
  [ "$(rex_wait "$W" 0)" = timeout ]
}

@test "rex_run_worker opens a window with no focus and the board env" {
  source "$SKILL_DIR/lib.sh"
  run rex_run_worker "$BATS_TEST_TMPDIR" fix-login "my board" fix-login-2 -- claude --name x
  [ "$status" -eq 0 ]
  new=$output
  [[ "$new" == block:* ]]
  rex_args window-new
  has_arg --focus=false
  has_arg "BOARD=my board"
  has_arg BOARD_ROLE=worker
  has_arg BOARD_SESSION=fix-login-2
  has_arg BOARD_NAME=fix-login
  has_arg "BOARD_ORCHESTRATOR=$O"
  has_arg claude
  [ -n "$(calls '^rex window new -s session:fake-1 ')" ]
  rec="$XDG_STATE_HOME/board-orchestrator-hc/rex/$new.json"
  jq -e '.role == "worker" and .board == "my board" and .session == "fix-login-2"
    and .rex_session == "session:fake-1"' "$rec"
  run rex_get "$new"
  [ "$status" -eq 0 ]
}

@test "rex_space_new opens a session, records it and shows it to the client" {
  source "$SKILL_DIR/lib.sh"
  unset REX_BLOCK REX_SESSION
  REX_CLIENT=client-1 run rex_space_new "my board" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == block:* ]]
  jq -e '.role == "orchestrator" and .board == "my board"' \
    "$XDG_STATE_HOME/board-orchestrator-hc/rex/$output.json"
  [ -n "$(calls '^rex new my board orchestrator --window orchestrator --cwd .* --json')" ]
  [ -n "$(calls '^rex -C client-1 do session.select --args ')" ]
}

@test "rex_full resolves an 8-hex suffix" {
  source "$SKILL_DIR/lib.sh"
  [ "$(rex_full "${W: -8}")" = "$W" ]
  [ "$(rex_full "$W")" = "$W" ]
  [ "$(rex_short "$W")" = "${W: -8}" ]
  run rex_full deadbeef
  [ "$status" -eq 1 ]
}

@test "rex_label maps the board labels into the record" {
  source "$SKILL_DIR/lib.sh"
  rex_label "$W" board.typed=card "board.session=s9"
  run rex_get "$W"
  jq -e '.labels["board.typed"] == "card" and .labels["board.session"] == "s9"' <<<"$output"
}

@test "rex_record exits 1 for a closed block and rex_record_rm deletes the file" {
  source "$SKILL_DIR/lib.sh"
  rex_record "$W" | jq -e '.role == "worker"'
  rex_record_set "$W" '{"name":"n2"}'
  [ "$(rex_record "$W" | jq -r .name)" = n2 ]
  rex_rm "$W"
  run rex_record "$W"
  [ "$status" -eq 1 ]
}

@test "rex_names lists the window labels of the session" {
  source "$SKILL_DIR/lib.sh"
  run rex_names
  [[ "$output" == *orchestrator* && "$output" == *worker-* ]]
}

@test "rex_read, rex_kill, rex_ping and the focus calls" {
  source "$SKILL_DIR/lib.sh"
  printf 'screen text\n' >"$FAKE_DIR/rex/capture.txt"
  [ "$(rex_read "$W")" = "screen text" ]
  [ -n "$(calls "^rex capture -s session:fake-1 -b $W")" ]
  rex_ping
  FAKE_REX_FAIL=1 run rex_ping
  [ "$status" -eq 1 ]
  REX_CLIENT=c1 rex_focus_agent "$W"
  [ -n "$(calls '^rex -C c1 do session.select --args .*window:w-')" ]
  [ -n "$(calls 'rex api call session.focus_block')" ]
  rex_kill "$W"
  run rex_get "$W"
  [ "$status" -eq 1 ]
}

@test "rex_space_close: 0 closed, 2 for a worker or an unknown block, 1 when the kill fails" {
  source "$SKILL_DIR/lib.sh"
  run rex_space_close "$W"
  [ "$status" -eq 2 ]
  run rex_space_close block:00000000-0000-0000-0000-00000000dead
  [ "$status" -eq 2 ]
  FAKE_REX_FAIL=1 run rex_space_close "$O"
  [ "$status" -eq 1 ]
  run rex_space_close "$O"
  [ "$status" -eq 0 ]
  [ -n "$(calls '^rex kill session:fake-1')" ]
}

@test "rex_tell_cmd and rex_tell_rule" {
  source "$SKILL_DIR/lib.sh"
  [ "$(rex_tell_cmd 'report a /r.md')" = "$HOME/.claude/skills/board-orchestrator/dispatch.sh tell \"report a /r.md\"" ]
  [ "$(rex_tell_rule)" = "Bash($HOME/.claude/skills/board-orchestrator/dispatch.sh tell *)" ]
  [[ "$(rex_tell_rule)" == "Bash(/"* ]]
}

@test "rex_space_close kills only a record with the orchestrator role" {
  source "$SKILL_DIR/lib.sh"
  rm "$XDG_STATE_HOME/board-orchestrator-hc/rex/$O.json"
  run rex_space_close "$O"
  [ "$status" -eq 2 ]
  rex_record_file "$O" '{"board":"b","role":"other","rex_session":"session:fake-1"}'
  run rex_space_close "$O"
  [ "$status" -eq 2 ]
  [ -z "$(calls '^rex kill')" ]
}

@test "rex_full and rex_record_set refuse an empty or unknown address" {
  source "$SKILL_DIR/lib.sh"
  run rex_full ""
  [ "$status" -eq 1 ]
  run rex_record_set deadbeef '{"name":"x"}'
  [ "$status" -eq 1 ]
  [ ! -e "$XDG_STATE_HOME/board-orchestrator-hc/rex/deadbeef.json" ]
}

@test "rex_run_worker needs -- before the command" {
  source "$SKILL_DIR/lib.sh"
  run rex_run_worker "$BATS_TEST_TMPDIR" n b s claude
  [ "$status" -eq 2 ]
  [[ "$output" == *"rex_run_worker needs -- before the command"* ]]
  [ -z "$(calls '^rex window new')" ]
}

@test "rex_send passes text that starts with a dash after --" {
  source "$SKILL_DIR/lib.sh"
  rex_send "$W" '-n text'
  [ -n "$(calls "^rex send -s session:fake-1 -b $W -- -n text")" ]
  rex_args send
  [ "${RUN_ARGS[4]}" = '-n text' ]
}
