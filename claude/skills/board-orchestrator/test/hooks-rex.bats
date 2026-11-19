#!/usr/bin/env bats
# hooks/guard.sh and hooks/compact.sh in a Renux pane (REX_BLOCK set).

bats_require_minimum_version 1.5.0
load helper

setup() { rex_setup; }

guard() {
  local json
  json=$(jq -cn --arg c "$1" --arg d "${2:-${REPO:-$BATS_TEST_TMPDIR}}" --arg s "${3:-s1}" \
    '{session_id: $s, cwd: $d, tool_name: "Bash", tool_input: {command: $c}}')
  run bash "$SKILL_DIR/hooks/guard.sh" <<<"$json"
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$output"; }

rex_worker() { export REX_BLOCK=b1 REX_SESSION=rs1 BOARD=garden BOARD_ROLE=worker BOARD_NAME=w1; }

blocked() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"board-orchestrator: a board worker cannot $1. Write it in the report: the orchestrator does it."* ]]
}

@test "guard blocks rex window new for a Rex worker" {
  rex_worker
  guard 'rex window new'
  blocked 'change the Renux window (rex window)'
}

@test "guard blocks rex do for a Rex worker" {
  rex_worker
  guard 'cd /tmp && rex do x'
  blocked 'change the Renux window (rex do)'
}

@test "guard blocks rex api call session.focus_block for a Rex worker" {
  rex_worker
  guard 'rex api call session.focus_block {}'
  blocked 'change the Renux window (rex api call session.focus_block)'
}

@test "guard blocks a prefixed full path rex kill for a Rex worker" {
  rex_worker
  guard 'FOO=1 /usr/bin/rex kill s'
  blocked 'change the Renux window (rex kill)'
}

@test "guard blocks rex server stop but allows rex server status" {
  rex_worker
  guard 'rex server stop'
  blocked 'change the Renux window (rex server stop)'
  guard 'rex server status'
  [ "$status" -eq 0 ]
}

@test "guard allows rex capture and rex api call session.view for a Rex worker" {
  rex_worker
  guard 'rex capture b1'
  [ "$status" -eq 0 ]
  guard 'rex api call session.view {}'
  [ "$status" -eq 0 ]
  guard 'rex --help'
  [ "$status" -eq 0 ]
}

@test "guard lets a Rex worker wait for a shared job" {
  rex_worker
  guard 'rex wait block:01a1 --for 3600s --json'
  [ "$status" -eq 0 ]
}

@test "guard allows a Rex worker a job tab with no focus in its session" {
  rex_worker
  for c in 'rex run -s "$REX_SESSION" --focus=false --keep-open --interactive --label t-test --cwd /tmp --json -- ~/.bin/when-free make test' \
    'rex run --session $REX_SESSION --focus=false -- make' 'rex run -s rs1 --focus=false -- make' 'rex run --focus=false -- make' \
    'rex run --session=rs1 --focus=false --wait -c /tmp --shell=none -- make' 'rex run --focus=false -- make -s rs2 --split=right' \
    'rex run --session "rs1" --focus=false --cwd "$PWD" --label="x" -- make'; do
    guard "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c: $output"; return 1; }
  done
}

@test "guard blocks a Rex worker a job tab with focus, in another session or with a split" {
  rex_worker
  guard 'rex run -s s1 --label x -- make'
  blocked 'change the Renux window (rex run)'
  for c in 'rex run -s "$REX_SESSION" --focus=true -- make' 'rex run -s rs2 --focus=false -- make' \
    'rex run --session=rs2 --focus=false -- make' 'rex run --focus=false --focus=true -- make' \
    'rex run --session rs2 --focus=false -- make' 'rex run -s "$REX_SESSION" --focus=false --split=right -- make' \
    'rex run --focus=false -b b2 --split right -- make' 'rex run --focus=false -w w9 -- make' \
    'rex run -srs2 --focus=false -- make' 'rex run -vs rs2 --focus=false -- make' \
    'rex run -s "$REX_SESSION" --label --focus=false -- make' 'rex run --focus=false --label -- -s rs2 -- make' \
    'rex run --focus=false make' 'REX_SESSION=rs2; rex run -s "$REX_SESSION" --focus=false -- make' \
    'export REX_SESSION=rs2 && rex run --session=$REX_SESSION --focus=false -- make' \
    'rex run --focus=false -c $(printf "/tmp --split=right") -- make' 'rex run --focus=false --label=x`echo --split=right` -- make' \
    'rex run --focus=false --label=x${A} -- make' 'rex run --focus=false --label "a -- b" --split=right -- make' \
    'X="a --split=right"; rex run --focus=false --label $X -- make' "rex run -s '\$REX_SESSION' --focus=false -- make"; do
    guard "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "guard allows a Rex worker to close a block, and blocks the other block calls" {
  rex_worker
  guard 'rex block close -s s1 block:01a1'
  [ "$status" -eq 0 ]
  guard 'rex block focus b9'
  blocked 'change the Renux window (rex block focus)'
}

@test "guard allows grep rex file" {
  rex_worker
  guard 'grep rex file'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# allowed COMMAND...: the guard lets each command run with no output.
allowed() {
  local c
  for c in "$@"; do
    guard "$c"
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "not allowed: $c: $output"; return 1; }
  done
}

# refused COMMAND...: the guard blocks each command.
refused() {
  local c
  for c in "$@"; do
    guard "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "guard does not split a quoted pipe or semicolon" {
  rex_worker
  allowed 'grep -n -i "herdr\|rex" Brewfile' \
    "systemctl --user list-units | grep -i -E 'hc|herdr|rex|renux'" \
    "pgrep -af 'hc.*core|rex'" \
    'echo "a; rex kill s"' \
    "echo a\\;rex kill s" \
    'grep "x\"; rex kill s" f' \
    'grep -n "herdr-app do" f' \
    "awk '/x/ { print \"rex window new\" }' f"
}

@test "guard does not read a heredoc body as a command" {
  rex_worker
  allowed $'cat > /tmp/x <<\'EOF\'\nrex kill s\nEOF\necho done' \
    $'cat <<-"EOF"\n\trex window new | x\n\tEOF' \
    $'cat <<EOF\nrex kill s $HOME\nEOF' \
    $'cat <<A <<B\nrex kill a\nA\nrex kill b\nB'
  refused $'cat <<EOF\n$(rex kill s)\nEOF' \
    $'cat <<EOF\n`rex kill s`\nEOF' \
    $'cat <<\'EOF\'\nrex ls\nEOF\nrex kill s'
}

@test "guard does not read a comment as a command" {
  rex_worker
  allowed '# rex kill s' $'echo a # rex kill s\necho b'
  refused $'# a comment\nrex kill s' 'echo a#b; rex kill s'
}

@test "guard allows the rex reads" {
  rex_worker
  allowed 'rex ls' 'rex ls --json 2>/dev/null | head -c 3000' 'rex list' \
    'rex wait b2 --for 110s --json' 'rex whoami' 'rex window rename --help' \
    'rex help window' \
    'rex api call com.superlogical.terminal.title "{\"session_id\":\"$REX_SESSION\",\"block_id\":\"$REX_BLOCK\"}"' \
    "rex api call com.superlogical.terminal.process '{}'" \
    "rex api call com.superlogical.terminal.program_status '{}'"
}

@test "guard finds rex in quotes, substitutions, shells and redirections" {
  rex_worker
  refused 'echo "$(rex kill s)"' 'echo "`rex kill s`"' 'x="$(echo "$(rex kill s)")"' \
    "bash -c 'rex kill s'" "sh -ec 'echo a; rex window new'" 'eval "rex kill s"' \
    "~/.bin/when-free bash -c 'rex kill s'" '{ rex kill s; }' \
    '2>/dev/null rex kill s' 'rex 2>/dev/null kill s' '>/tmp/o rex kill s' \
    "x='a;b'; rex kill s" 'echo $( (rex kill s) )' $'rex \\\nkill s' \
    "rex api call com.superlogical.terminal.write '{}'" 'rex api call "$m" {}' \
    'rex ls; rex kill s' 'echo $((1 + 2)); rex kill s' 'cat <<<"x" ; rex kill s' \
    'rex run -- sh'
}

@test "guard finds rex in a shell -c after options or a prefix with options" {
  rex_worker
  refused "bash -euo pipefail -c 'echo a; rex kill s'" "bash -o pipefail -c 'set -e; rex kill s'" \
    "timeout 10 bash -c 'echo a; rex kill s'" 'nice -n 5 bash -c "a; rex kill s"' \
    'hc run --bg -- bash -c "a; rex kill s"' "find . -exec sh -c 'echo; rex kill s' \\;" \
    'echo s | xargs -I{} rex kill {}' 'echo s | xargs -n 1 rex kill' 'sudo -E rex kill s' \
    'env -u X rex kill s' 'timeout 10 rex kill s' 'nice -n 5 rex kill s'
}

@test "guard reads a heredoc fed to a shell as commands" {
  rex_worker
  refused $'bash <<\'EOF\'\necho a\nrex kill s\nEOF' $'sh <<EOF\nrex kill s\nEOF' \
    $'cat <<\'EOF\' | bash\nrex kill s\nEOF' $'bash -s <<-EOF\n\trex kill s\n\tEOF'
  allowed $'bash <<\'EOF\'\nrex ls\nEOF'
}

@test "guard keeps the heredoc list of a body apart" {
  rex_worker
  refused $'cat <<EOF\n$(echo a\nrex kill s)\nEOF' $'cat <<EOF\n`echo a\nrex kill s`\nEOF'
}

@test "guard does not read an arithmetic shift as a heredoc" {
  rex_worker
  refused $'x=$((1 << 2))\nrex kill s' $'(( x <<= 1 ))\nrex kill s' \
    $'echo a <<<"$((1<<2))"\nrex kill s' 'echo ${x:-a #}; rex kill s' \
    'echo ${x:-$(rex kill s)}'
  allowed 'echo $((1 << 2)) ${x:-"a | rex kill"}'
}

@test "guard checks the command of a job tab" {
  rex_worker
  allowed "rex run -s \"\$REX_SESSION\" --focus=false --label 'a | b' -- ~/.bin/when-free bash -c 'make test; echo \"rex | x\"'"
  refused 'rex run --focus=false -- rex kill s' "rex run --focus=false -- bash -c 'a; rex window new'"
}

@test "guard does not allow a --help after --" {
  rex_worker
  refused 'rex run -s S -- mytool --help'
}

@test "guard scans a big command fast" {
  rex_worker
  local line big=""
  line='echo "value $HOME | rex" $(date) # c'
  while [ "${#big}" -lt 50000 ]; do big+="$line"$'\n'; done
  local start=$SECONDS
  for c in "$big" "echo \"$big\"" "bash -c '$big'" $'cat <<EOF\n'"$big"$'EOF'; do
    allowed "$c"
  done
  [ $((SECONDS - start)) -le 3 ]
}

@test "guard does nothing for a Rex orchestrator" {
  export REX_BLOCK=b1 BOARD=garden BOARD_ROLE=orchestrator
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does nothing for a Rex pane with no BOARD_ROLE" {
  export REX_BLOCK=b1
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the push rules apply to a Rex worker" {
  rex_worker
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  ORIGIN="$BATS_TEST_TMPDIR/origin.git" REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/master
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b master
  git -C "$REPO" commit -q --allow-empty -m one
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin master
  git -C "$REPO" remote set-head origin master
  mkdir -p "$REPO/.claude"
  printf '{"env":{"BOARD_PUSH_POLICY":"branch"}}\n' >"$REPO/.claude/settings.local.json"
  git -C "$REPO" checkout -q -b feat
  git -C "$REPO" commit -q --allow-empty -m two
  guard 'git push -u origin HEAD'
  [ "$status" -eq 0 ]
  [ "$(decision)" = ask ]
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" == *"first push of the branch feat"* ]]
}

@test "compact tells a Rex orchestrator to read the skill again" {
  export REX_BLOCK=b1 BOARD="my board" BOARD_ROLE=orchestrator
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *'"my board"'* ]]
}

@test "compact gives a Rex worker the file of its first prompt" {
  export REX_BLOCK=b1 BOARD="my board" BOARD_ROLE=worker BOARD_SESSION=s1
  f=$(prompt_file s1 'Fix the login bug.')
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = SessionStart ]
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
  [[ "$ctx" == *"a worker of the board my board"* ]]
  [[ "$ctx" == *"Before any other action, read $f with the Read tool"* ]]
  [[ "$ctx" == *"Do not start the card again"* ]]
  [[ "$ctx" == *"the file wins, with one exception: a request or a decision of the user after the first prompt wins over the file."* ]]
}

@test "compact is silent for a Rex worker with no prompt file or a bad session" {
  export REX_BLOCK=b1 BOARD="my board" BOARD_ROLE=worker BOARD_SESSION=s1
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  mkdir -p "$XDG_STATE_HOME/board-orchestrator-hc/prompts"
  printf x >"$XDG_STATE_HOME/board-orchestrator-hc/s1.md"
  export BOARD_SESSION=../s1
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard finds rex inside a command" {
  rex_worker
  local c
  for c in 'id=$(rex window new)' 'for b in x y; do rex kill $b; done' 'if rex kill s; then :; fi' \
    '(rex kill s)' 'echo `rex kill s`' 'time rex kill s' 'xargs rex kill' 'env X=1 "rex" kill s'; do
    guard "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "guard names a bare rex with no trailing space" {
  rex_worker
  guard 'rex'
  blocked 'change the Renux window (rex)'
}

@test "guard does nothing for a Rex worker pane with no BOARD" {
  export REX_BLOCK=b1 BOARD_ROLE=worker
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard does nothing for a non-board pane" {
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard and compact do nothing outside Renux, even with a board env" {
  unset REX_BLOCK REX_SESSION
  export BOARD=garden BOARD_ROLE=worker
  guard 'rex window new'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  export BOARD_ROLE=orchestrator
  run bash "$SKILL_DIR/hooks/compact.sh" <<<'{"source":"compact"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
