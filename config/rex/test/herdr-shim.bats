#!/usr/bin/env bats
# herdr-shim: the herdr calls of reviewr's Send (agent list, pane send-text, agent focus),
# answered from a fake rex. Send waits for each call, so a call reads only the session and
# the tab of reviewr when they hold the answer.

load helper

setup() {
  rex_setup
  # herdr-shim runs rex from PATH, with ~/.local/bin first.
  mkdir -p "$HOME/.local/bin"
  # The session s9 is gone: its session.list_blocks fails.
  printf '#!/usr/bin/env bash\n[[ "$*" != *session.list_blocks*s9* ]] || exit 1\nexec %q "$@"\n' \
    "$FAKES/fake-rex" >"$HOME/.local/bin/rex"
  chmod +x "$HOME/.local/bin/rex"
  # Session s1: the tab w1 has the agent b1 and reviewr (b2), the tab w2 has the agent b4.
  # Session s2: the agent b3.
  fake_block s1 b1 w1 agent
  fake_block s1 b2 w1 reviewr shell
  fake_block s1 b4 w2 other
  fake_block s2 b3 w3 far
  printf '{"records":[]}\n' >"$FAKE_DIR/rex/status-b2.json"
  export HERDR_WORKSPACE_ID=s1 HERDR_TAB_ID=w1 HERDR_PANE_ID=b2
}

shim() { "$BIN/herdr-shim" "$@"; }

@test "agent list in a tab with an agent gives that agent" {
  run shim agent list
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.result.agents[] | [.pane_id, .tab_id, .workspace_id, .agent, .agent_status]]' <<<"$output")" = \
    '[["b1","w1","s1","claude","working"]]' ]
  [ "$(jq -r '.result.agents[0].cwd' <<<"$output")" = /home/user/.workspace/dotfiles ]
  [ "$(jq -r '.result.agents[0].name' <<<"$output")" = agent ]
}

@test "agent list in a tab with an agent reads only the blocks of that tab" {
  run shim agent list
  [ "$status" -eq 0 ]
  [ -z "$(calls 'api call session\.list \{')" ]
  [ -z "$(calls 'session_id":"s2')" ]
  [ -z "$(calls 'block_id":"b4')" ]
}

@test "agent list in a tab with no agent gives each agent of each session in order" {
  HERDR_TAB_ID=w9 run shim agent list
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.result.agents[].pane_id]' <<<"$output")" = '["b1","b4","b3"]' ]
}

@test "agent list with no tab gives each agent of each session in order" {
  unset HERDR_TAB_ID HERDR_WORKSPACE_ID
  run shim agent list
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.result.agents[].pane_id]' <<<"$output")" = '["b1","b4","b3"]' ]
}

@test "pane send-text to a block of the session of reviewr reads only that session" {
  run shim pane send-text b1 $'\e[200~hello\e[201~'
  [ "$status" -eq 0 ]
  [ "$(tr '\0' ' ' <"$FAKE_DIR/rex/rex-send-1.args")" = "-s s1 -b b1 hello " ]
  [ -z "$(calls 'api call session\.list \{')" ]
  [ -n "$(calls '^rex send-key -s s1 -b b1 enter$')" ]
}

@test "pane send-text to a block of another session finds its session" {
  run shim pane send-text b3 hello
  [ "$status" -eq 0 ]
  [ "$(tr '\0' ' ' <"$FAKE_DIR/rex/rex-send-1.args")" = "-s s2 -b b3 hello " ]
}

@test "agent focus on a block of the session of reviewr reads only that session" {
  run shim agent focus b1
  [ "$status" -eq 0 ]
  [ -n "$(calls 'session\.focus_block \{"session_id":"s1","block_id":"b1"\}')" ]
  [ -z "$(calls 'api call session\.list \{')" ]
}

@test "agent list leaves no temp folder" {
  run shim agent list
  [ "$status" -eq 0 ]
  HERDR_TAB_ID=w9 run shim agent list
  [ "$status" -eq 0 ]
  [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'herdr-shim.*')" ]
}

@test "agent list when the session of reviewr is gone falls back to the scan of each session" {
  HERDR_WORKSPACE_ID=s9 run shim agent list
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.result.agents[].pane_id]' <<<"$output")" = '["b1"]' ]
}

@test "pane send-text when the session of reviewr is gone finds the session of the block" {
  HERDR_WORKSPACE_ID=s9 run shim pane send-text b3 hello
  [ "$status" -eq 0 ]
  [ "$(tr '\0' ' ' <"$FAKE_DIR/rex/rex-send-1.args")" = "-s s2 -b b3 hello " ]
}
