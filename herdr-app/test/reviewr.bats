#!/usr/bin/env bats
# herdr-shim (the herdr calls of herdr-reviewr on hc) and agent-tabs.sh reviewr.

bats_require_minimum_version 1.5.0
load helper

SHIM="$BATS_TEST_DIRNAME/../bin/herdr-shim"

setup() {
  hc_setup
  printf '{"terminals":[{"address":"t5","agent":"claude-code","state":"live"},{"address":"t6","agent":"zsh","state":"live"},{"address":"t7","agent":"herdr-reviewr","state":"live"}]}\n' >"$FAKE_DIR/hc-ls.json"
  jq -n '{address: "t5", state: "live", foreground: {name: "claude", cwd: "/r"}, name: null,
    status: {app: "claude-code", state: "idle"},
    labels: {"herdr.space": "sp1", "herdr.tab": "tb1"}}' >"$FAKE_DIR/hc-get-t5.json"
  jq -n '{address: "t6", state: "live", foreground: {name: "zsh", cwd: "/r"}, status: null,
    labels: {"herdr.space": "sp1", "herdr.tab": "tb1"}}' >"$FAKE_DIR/hc-get-t6.json"
  jq -n '{address: "t7", state: "live", foreground: {name: "herdr-reviewr", cwd: "/r"}, status: null,
    labels: {"herdr.space": "sp1", "herdr.tab": "tb1"}}' >"$FAKE_DIR/hc-get-t7.json"
}

shim() { run bash "$SHIM" "$@"; }

@test "agent list gives the agents with the herdr fields" {
  shim agent list
  [ "$status" -eq 0 ]
  [ "$(jq -c '.result.agents' <<<"$output")" = '[{"agent":"claude","agent_status":"idle","pane_id":"t5","tab_id":"tb1","workspace_id":"sp1","cwd":"/r","name":null}]' ]
}

@test "agent list keeps only the agents of the reviewr tab, when that tab has one" {
  printf '{"terminals":[{"address":"t5","state":"live"},{"address":"t8","state":"live"}]}\n' >"$FAKE_DIR/hc-ls.json"
  jq -n '{address: "t8", state: "live", foreground: {name: "claude", cwd: "/o"},
    status: {app: "claude-code", state: "idle"},
    labels: {"herdr.space": "sp1", "herdr.tab": "tb2"}}' >"$FAKE_DIR/hc-get-t8.json"
  HERDR_TAB_ID=tb2 shim agent list
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.result.agents[].pane_id]' <<<"$output")" = '["t8"]' ]
  HERDR_TAB_ID=tb3 shim agent list
  [ "$(jq -c '[.result.agents[].pane_id]' <<<"$output")" = '["t5","t8"]' ]
}

@test "pane send-text sends the text without the paste markers" {
  shim pane send-text t5 $'\e[200~Fix line 3\nand line 4\e[201~'
  [ "$status" -eq 0 ]
  [ -n "$(calls '^hc send t5 Fix line 3$')" ]
  [ -n "$(calls '^and line 4$')" ]
  [ -z "$(grep -c $'\e' "$FAKE_LOG" | grep -v '^0$')" ]
}

@test "agent focus shows the agent in herdr-app" {
  shim agent focus t5
  [ "$status" -eq 0 ]
  [ -n "$(calls '^herdr-app do agent.focus --terminal t5')" ]
}

@test "tab list gives the tabs of the space" {
  printf '{"spaces":[{"id":"sp1","tabs":[{"id":"tb1","name":"main"},{"id":"tb2","name":null}]},{"id":"sp2","tabs":[{"id":"tb9","name":"x"}]}]}\n' >"$FAKE_DIR/app-ls.json"
  shim tab list --workspace sp1
  [ "$status" -eq 0 ]
  [ "$(jq -c '.result.tabs' <<<"$output")" = '[{"tab_id":"tb1","label":"main"},{"tab_id":"tb2","label":null}]' ]
}

@test "pane list, pane rename and plugin config-dir answer" {
  shim pane list --workspace sp1
  [ "$status" -eq 0 ]
  [ "$(jq -c '.result.panes' <<<"$output")" = '[]' ]
  shim pane rename t7 reviewr
  [ "$status" -eq 0 ]
  shim plugin config-dir persiyanov.reviewr
  [ "$output" = "$(cd "$BATS_TEST_DIRNAME/../reviewr" && pwd)" ]
}

@test "an unknown herdr call fails" {
  shim workspace list
  [ "$status" -ne 0 ]
}

@test "reviewr runs herdr-reviewr with the shim and the ids of its terminal" {
  export HC_TERMINAL_ID=t7
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$HERDR_BIN_PATH" "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID" "$1" "$HERDR_PLUGIN_CONFIG_DIR"\n' >"$BATS_TEST_TMPDIR/fake-reviewr"
  chmod +x "$BATS_TEST_TMPDIR/fake-reviewr"
  REVIEWR_BIN="$BATS_TEST_TMPDIR/fake-reviewr" run bash "$AT" reviewr /r
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$BATS_TEST_DIRNAME/../bin" && pwd)/herdr-shim" ]
  [ "${lines[1]}" = sp1 ]
  [ "${lines[2]}" = tb1 ]
  [ "${lines[3]}" = t7 ]
  [ "${lines[4]}" = /r ]
  [ "${lines[5]}" = "$(cd "$BATS_TEST_DIRNAME/../reviewr" && pwd)" ]
  [ -f "${lines[5]}/config.toml" ]
}

@test "reviewr with a base starts in the branch scope on that base" {
  export HC_TERMINAL_ID=t7
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$HERDR_PLUGIN_CONFIG_DIR" "$@"\n' >"$BATS_TEST_TMPDIR/fake-reviewr"
  chmod +x "$BATS_TEST_TMPDIR/fake-reviewr"
  REVIEWR_BIN="$BATS_TEST_TMPDIR/fake-reviewr" run bash "$AT" reviewr /r abc1234
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$BATS_TEST_DIRNAME/../reviewr-branch" && pwd)" ]
  grep -qx 'default_scope = "branch"' "${lines[0]}/config.toml"
  [ "${lines[1]}" = --base ]
  [ "${lines[2]}" = abc1234 ]
  [ "${lines[3]}" = /r ]
}
