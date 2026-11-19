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
