#!/usr/bin/env bats

load helper

setup() {
  br_setup
  export PATH="$WRAP:$FAKES:$PATH"
}

@test "sql runs psql in a read-only transaction with a timeout" {
  cd "$HOME/ws/alpha/db1"
  run board-ro sql db1 "select 1"
  [ "$status" -eq 0 ]
  [ "$output" = $'a,b\n1,2' ]
  grep -q 'default_transaction_read_only=on' "$FAKE_LOG"
  grep -q 'statement_timeout=30s' "$FAKE_LOG"
  grep -q -- '--csv' "$FAKE_LOG"
  grep -q -- '-c select 1' "$FAKE_LOG"
}

@test "sql reads the connection URL from the first line of the pass entry" {
  cd "$HOME/ws/alpha/db1"
  run board-ro sql db1 "select 1"
  grep -qx 'pass show alpha/db-readonly/db1' "$FAKE_LOG"
  grep -q -- '-d postgres://ro:secret@db.test/x -c' "$FAKE_LOG"
  ! grep -q 'second line' "$FAKE_LOG"
}

@test "sql refuses a database of another board" {
  cd "$HOME/ws/beta"
  run board-ro sql db1 "select 1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no database db1"* ]]
  ! grep -q '^pass' "$FAKE_LOG"
}

@test "sql refuses a name that is only a prefix" {
  cd "$HOME/ws/alpha"
  run board-ro sql tok "select 1"
  [ "$status" -eq 2 ]
  ! grep -q '^pass' "$FAKE_LOG"
}

@test "sql ignores a comment line in the databases file" {
  cd "$HOME/ws/alpha"
  run board-ro sql '#' "select 1"
  [ "$status" -eq 2 ]
}

@test "sql outside a board exits 2 and says so" {
  cd "$HOME"
  run board-ro sql db1 "select 1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no board"* ]]
}

@test "sql with a missing query exits 2" {
  cd "$HOME/ws/alpha"
  run board-ro sql db1
  [ "$status" -eq 2 ]
}

@test "a psql error keeps its exit code and does not show the URL" {
  cd "$HOME/ws/alpha"
  FAKE_PSQL_FAIL=1 run board-ro sql db1 "delete from x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-only transaction"* ]]
  [[ "$output" != *"postgres://"* ]]
}

@test "list shows the databases and the notebooks folder, not the pass entries" {
  cd "$HOME/ws/alpha/db1"
  run board-ro list
  [ "$status" -eq 0 ]
  [[ "$output" == *"board: alpha"* ]]
  [[ "$output" == *"databases: db1"* ]]
  [[ "$output" == *"notebooks: $HOME/ws/alpha/notebooks"* ]]
  [[ "$output" != *"db-readonly"* ]]
}

@test "list in a board with no database says none" {
  cd "$HOME/ws/beta"
  run board-ro list
  [ "$status" -eq 0 ]
  [[ "$output" == *"databases: none"* ]]
}

@test "notebook makes a dated file from the template in a git repo" {
  cd "$HOME/ws/alpha/db1"
  run board-ro notebook "Count the rows!"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/ws/alpha/notebooks/$(date +%F)-count-the-rows.livemd" ]
  [ -d "$HOME/ws/alpha/notebooks/.git" ]
  grep -qx '# Count the rows!' "$output"
  grep -q 'board-ro' "$output"
}

@test "notebook does not overwrite an existing file" {
  cd "$HOME/ws/alpha"
  f=$(board-ro notebook topic)
  echo mine >"$f"
  run board-ro notebook topic
  [ "$output" = "$f" ]
  [ "$(cat "$f")" = mine ]
}

@test "notebook in a board with no notebooks folder exits 2" {
  cd "$HOME/ws/beta"
  run board-ro notebook topic
  [ "$status" -eq 2 ]
}

@test "an unknown command exits 2 with the usage" {
  cd "$HOME/ws/alpha"
  run board-ro nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

# board_mcp JSON: the mcpServers object of the board alpha.
board_mcp() { printf '{"mcpServers":%s}\n' "$1" >"$BOARD_RESOURCES_HOME/alpha/mcp.json"; }

# mcp_list LINE...: the output of the fake "claude mcp list".
mcp_list() {
  export FAKE_MCP_LIST="$BATS_TEST_TMPDIR/mcp-list"
  printf 'Checking MCP server health…\n\n' >"$FAKE_MCP_LIST"
  printf '%s\n' "$@" >>"$FAKE_MCP_LIST"
}

HTTP_A='{"aiven":{"type":"http","url":"https://a.test/mcp"}}'

@test "check passes when each MCP server connects and each database answers" {
  cd "$HOME/ws/alpha/db1"
  board_mcp "$HTTP_A"
  mcp_list 'aiven: https://a.test/mcp (HTTP) - ✔ Connected'
  run board-ro check
  [ "$status" -eq 0 ]
  [ "$output" = "board-ro check: all logins work (1 MCP servers, 1 databases)" ]
}

@test "check reports an MCP server that needs authentication" {
  cd "$HOME/ws/alpha/db1"
  board_mcp "$HTTP_A"
  mcp_list 'aiven: https://a.test/mcp (HTTP) - ! Needs authentication'
  run board-ro check
  [ "$status" -eq 1 ]
  [ "$output" = "mcp aiven: Needs authentication. Fix: run /mcp in this pane, pick aiven, and log in." ]
}

@test "check merges the board mcp.json and the repo .mcp.json" {
  cd "$HOME/ws/alpha/db1"
  git init -q .
  mkdir sub && cd sub
  board_mcp "$HTTP_A"
  printf '{"mcpServers":{"forgejo":{"command":"forgejo-mcp"}}}\n' >"$HOME/ws/alpha/db1/.mcp.json"
  mcp_list 'aiven: https://a.test/mcp (HTTP) - ✔ Connected' 'forgejo: forgejo-mcp - ✔ Connected'
  run board-ro check
  [ "$status" -eq 0 ]
  grep '^mcp.json ' "$FAKE_LOG" | sed 's/^mcp.json //' | jq -e '.mcpServers | keys == ["aiven","forgejo"]'
}

@test "check approves the scratch servers and runs the real claude" {
  cd "$HOME/ws/alpha/db1"
  board_mcp "$HTTP_A"
  mcp_list 'aiven: https://a.test/mcp (HTTP) - ✔ Connected'
  run board-ro check
  [ "$status" -eq 0 ]
  [ "$(grep -A1 -x -- --settings "$FAKE_LOG" | tail -1)" = '{"enableAllProjectMcpServers":true}' ]
  grep -qx mcp "$FAKE_LOG"
  grep -qx list "$FAKE_LOG"
  ! grep -q -- '--mcp-config' "$FAKE_LOG"
}

@test "check ignores the servers of other scopes" {
  cd "$HOME/ws/alpha/db1"
  board_mcp "$HTTP_A"
  mcp_list 'superlogical: https://s.test (HTTP) - ✘ Failed to connect' \
    'aiven: https://a.test/mcp (HTTP) - ✔ Connected'
  run board-ro check
  [ "$status" -eq 0 ]
  [[ "$output" != *superlogical* ]]
}

@test "check reports a merged server that is not in the list" {
  cd "$HOME/ws/alpha/db1"
  board_mcp '{"aiven":{"type":"http","url":"https://a.test/mcp"},"forgejo":{"command":"f"}}'
  mcp_list 'aiven: https://a.test/mcp (HTTP) - ✔ Connected'
  run board-ro check
  [ "$status" -eq 1 ]
  [[ "$output" == "mcp forgejo: not in the list. Fix: "* ]]
}

@test "check matches the server name exactly" {
  cd "$HOME/ws/alpha/db1"
  board_mcp '{"a.b":{"command":"x"},"axb":{"command":"y"}}'
  mcp_list 'axb: y - ✘ Failed to connect' 'a.b: x - ✔ Connected'
  run board-ro check
  [ "$status" -eq 1 ]
  [[ "$output" == "mcp axb: Failed to connect. Fix: "* ]]
  [[ "$output" != *"mcp a.b"* ]]
}

@test "check gives the bao hint for a failed server that reads bao" {
  cd "$HOME/ws/alpha/db1"
  board_mcp '{"forgejo":{"command":"sh","args":["-c","T=$(bao kv get -field=token x) && exec f"]}}'
  mcp_list 'forgejo: sh -c T=... - ✘ Failed to connect'
  run board-ro check
  [ "$status" -eq 1 ]
  [[ "$output" == "mcp forgejo: Failed to connect. Fix: "* ]]
  [[ "$output" == *"bao login"* ]]
  [[ "$output" == *"/mcp"* ]]
}

@test "check reports an MCP check that does not end" {
  cd "$HOME/ws/alpha/db1"
  board_mcp "$HTTP_A"
  mcp_list 'aiven: https://a.test/mcp (HTTP) - ✔ Connected'
  start=$SECONDS
  FAKE_CLAUDE_SLEEP=5 BOARD_CHECK_TIMEOUT=1 run board-ro check
  [ "$status" -eq 1 ]
  [[ "$output" == "mcp: the check did not end in 1 s."* ]]
  [ $((SECONDS - start)) -lt 4 ]
}

@test "check with no MCP servers runs no claude" {
  cd "$HOME/ws/alpha/db1"
  mcp_list
  run board-ro check
  [ "$status" -eq 0 ]
  [ "$output" = "board-ro check: all logins work (0 MCP servers, 1 databases)" ]
  ! grep -qx mcp "$FAKE_LOG"
}

@test "check reports a database whose login fails" {
  cd "$HOME/ws/alpha/db1"
  FAKE_PSQL_FAIL=1 run board-ro check
  [ "$status" -eq 1 ]
  [[ "$output" == "db db1: ERROR:  cannot execute"* ]]
  [[ "$output" == *"alpha/db-readonly/db1"* ]]
  [[ "$output" != *"postgres://"* ]]
  grep -q -- '-c select 1' "$FAKE_LOG"
}

@test "check runs pass with no pinentry" {
  cd "$HOME/ws/alpha/db1"
  run board-ro check
  grep -qx 'PASSWORD_STORE_GPG_OPTS=--pinentry-mode error' "$FAKE_LOG"
}

@test "check reports a pass entry that fails" {
  cd "$HOME/ws/alpha/db1"
  FAKE_PASS_FAIL=1 run board-ro check
  [ "$status" -eq 1 ]
  [[ "$output" == "db db1: gpg: decryption failed: No secret key. Fix: "* ]]
  [[ "$output" == *gpg-unlock* ]]
  [[ "$output" == *"alpha/db-readonly/db1"* ]]
  ! grep -q '^psql' "$FAKE_LOG"
}

@test "check exits 2 outside a board" {
  cd "$HOME"
  run board-ro check
  [ "$status" -eq 2 ]
}
