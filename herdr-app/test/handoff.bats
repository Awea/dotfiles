#!/usr/bin/env bats
# agent-tabs.sh handoff and handoff-start.

bats_require_minimum_version 1.5.0
load helper

setup() {
  hc_setup
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  printf '{"tab":"tbnew","terminal":"t8"}\n' >"$FAKE_DIR/app-do.json"
  # hc send writes the handoff document, as the /handoff skill does.
  cat >"$FAKE_DIR/on-send" <<'HOOK'
#!/usr/bin/env bash
text=${!#}
doc=${text##*Save the handoff document to }
[ "$doc" = "$text" ] || printf '# Handoff\n' >"$doc"
HOOK
  chmod +x "$FAKE_DIR/on-send"
}

# source_claude STATE [TITLE]: the focused claude t5.
source_claude() {
  jq -n --arg s "$1" --arg t "${2:-Fix flaky test}" --arg cwd "$REPO" \
    '{address: "t5", state: "live", title: $t, foreground: {name: "claude", cwd: $cwd},
      status: {app: "claude-code", state: $s}, labels: {}}' >"$FAKE_DIR/hc-get-t5.json"
}

handoff() { run bash "$AT" handoff t5 sp1 tbold "${1-Fix the tests}" "${2-high}" "${3-focus}"; }

# app_args N: the arguments of the Nth herdr-app do call in APP_ARGS.
app_args() { mapfile -d '' APP_ARGS <"$FAKE_DIR/app-do-$1.args"; }
app_after() {
  local i
  for i in "${!APP_ARGS[@]}"; do
    [ "${APP_ARGS[$i]}" != "$1" ] || { printf '%s\n' "${APP_ARGS[$((i + 1))]}"; return 0; }
  done
  return 1
}

@test "handoff refuses a source that is not an idle claude" {
  source_claude working
  handoff
  [ "$status" -eq 1 ]
  [ -z "$(calls '^hc send')" ]
  app_args 1
  [ "$(app_after --name)" = "handoff failed" ]
}

@test "handoff waits while the source claude is blocked" {
  source_claude idle
  rm "$FAKE_DIR/on-send"
  # The send leaves the source blocked. One second later the user approves: the source
  # is idle and the document is written.
  cat >"$FAKE_DIR/on-send" <<'HOOK'
#!/usr/bin/env bash
text=${!#}
doc=${text##*Save the handoff document to }
f="$FAKE_DIR/hc-get-t5.json"
jq '.status.state = "blocked"' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
( sleep 1
  jq '.status.state = "idle"' "$f" >"$f.tmp2" && mv "$f.tmp2" "$f"
  printf '# Handoff\n' >"$doc" ) </dev/null >/dev/null 2>&1 &
HOOK
  chmod +x "$FAKE_DIR/on-send"
  AGENT_TABS_HANDOFF_WAIT=20 handoff
  [ "$status" -eq 0 ]
  app_args 1
  [ "$(jq -r '.[0]' <<<"$(app_after --argv)")" = claude ]
}

@test "handoff does not spin while the source stays blocked" {
  source_claude idle
  rm "$FAKE_DIR/on-send"
  printf '#!/usr/bin/env bash\nf="$FAKE_DIR/hc-get-t5.json"; jq ".status.state = \\"blocked\\"" "$f" >"$f.tmp" && mv "$f.tmp" "$f"\n' >"$FAKE_DIR/on-send"
  chmod +x "$FAKE_DIR/on-send"
  printf '{"ended":true,"reason":"status","status":"blocked"}\n' >"$FAKE_DIR/hc-wait.json"
  AGENT_TABS_HANDOFF_WAIT=3 handoff
  [ "$status" -eq 1 ]
  # About one check every 2 seconds, not a tight loop.
  [ "$(calls '^hc (get|wait) t5' | wc -l)" -le 8 ]
}

@test "handoff opens the new tab in the folder of the source, also in a worktree" {
  git init -q "$BATS_TEST_TMPDIR/main"
  git -C "$BATS_TEST_TMPDIR/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$BATS_TEST_TMPDIR/main" worktree add -q "$BATS_TEST_TMPDIR/wt"
  REPO="$BATS_TEST_TMPDIR/wt"
  source_claude idle
  handoff
  app_args 1
  [ "$(app_after --folder)" = "$BATS_TEST_TMPDIR/wt" ]
}

@test "handoff sends /handoff with the focus and the doc path" {
  source_claude idle
  handoff
  [ "$status" -eq 0 ]
  [ -n "$(calls '^hc send --wait --timeout 900 t5 /handoff Fix the tests\. Save the handoff document to /.*herdr-handoff-.*\.md$')" ]
}

@test "handoff keeps quotes and spaces" {
  source_claude done
  handoff "it's \"x\" y"
  [ "$status" -eq 0 ]
  [ -n "$(calls "^hc send --wait --timeout 900 t5 /handoff it's \"x\" y\\. Save")" ]
  app_args 1
  [ "$(jq -r '.[2]' <<<"$(app_after --argv)")" = "it's \"x\" y" ]
}

@test "handoff opens a claude tab with the title, effort and task" {
  source_claude idle
  handoff
  app_args 1
  [ "${APP_ARGS[1]}" = tab.new ]
  [ "$(app_after --space)" = sp1 ]
  [ "$(app_after --folder)" = "$REPO" ]
  [ "$(jq -c . <<<"$(app_after --argv)")" = '["claude","-n","Fix the tests","--effort","high"]' ]
  [[ "$(app_after --task)" == "Read the handoff document at "*", then continue the work." ]]
}

@test "handoff with no focus text names the tab after the source title" {
  source_claude idle "Relay numbers"
  handoff "" ""
  app_args 1
  [ "$(jq -c . <<<"$(app_after --argv)")" = '["claude","-n","Relay numbers handoff"]' ]
}

@test "handoff in the background shows the source tab again" {
  source_claude idle
  handoff "Fix the tests" high background
  app_args 2
  [ "${APP_ARGS[1]}" = tab.select ]
  [ "$(app_after --id)" = tbold ]
}

@test "handoff opens a shell tab with the error when the doc stays empty" {
  source_claude idle
  rm "$FAKE_DIR/on-send"
  handoff
  [ "$status" -eq 1 ]
  app_args 1
  [ "$(app_after --name)" = "handoff failed" ]
  [ "$(jq -r '.[0:2] | join(" ")' <<<"$(app_after --argv)")" = "sh -c" ]
}

@test "handoff gives up after the 15 minute wait" {
  source_claude idle
  rm "$FAKE_DIR/on-send"
  printf '#!/usr/bin/env bash\nf="$FAKE_DIR/hc-get-t5.json"; jq ".status.state = \\"working\\"" "$f" >"$f.tmp" && mv "$f.tmp" "$f"\n' >"$FAKE_DIR/on-send"
  chmod +x "$FAKE_DIR/on-send"
  printf '{"ended":false,"reason":"timeout"}\n' >"$FAKE_DIR/hc-wait.json"
  AGENT_TABS_HANDOFF_WAIT=1 handoff
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not end"* ]]
  app_args 1
  [ "$(app_after --name)" = "handoff failed" ]
}

@test "handoff-start returns at once" {
  source_claude idle
  export FAKE_WAIT_SLEEP=3
  start=$(date +%s)
  run bash "$AT" handoff-start t5 sp1 tbold "Fix" "" focus
  [ "$status" -eq 0 ]
  [ $(($(date +%s) - start)) -le 1 ]
}
