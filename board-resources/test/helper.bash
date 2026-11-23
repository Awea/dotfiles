# shellcheck shell=bash
# Common setup for the board-resources tests.

# shellcheck disable=SC2034 # Used by the test files.
BR_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
WRAP="$BR_DIR/bin"
FAKES="$BATS_TEST_DIRNAME/fakes"

# shellcheck disable=SC2088 # The configs hold a literal ~.
br_setup() {
  # On macOS, TMPDIR is under /var, a link to /private/var: use the real path.
  BATS_TEST_TMPDIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export BOARD_RESOURCES_HOME="$BATS_TEST_TMPDIR/config"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$HOME/ws/alpha/db1" "$HOME/ws/beta" "$BOARD_RESOURCES_HOME/alpha" "$BOARD_RESOURCES_HOME/beta"
  : >"$FAKE_LOG"
  unset BOARD_RESOURCES_OFF FAKE_PSQL_FAIL FAKE_PASS_FAIL FAKE_MCP_LIST FAKE_CLAUDE_SLEEP BOARD_CHECK_TIMEOUT
  printf '~/ws/alpha\n' >"$BOARD_RESOURCES_HOME/alpha/roots"
  printf '# name pass-entry\ndb1 alpha/db-readonly/db1\n' >"$BOARD_RESOURCES_HOME/alpha/databases"
  printf '~/ws/alpha/notebooks\n' >"$BOARD_RESOURCES_HOME/alpha/notebooks"
  printf '{"mcpServers":{}}\n' >"$BOARD_RESOURCES_HOME/alpha/mcp.json"
  printf '{"permissions":{"allow":["Bash(board-ro *)"]}}\n' >"$BOARD_RESOURCES_HOME/alpha/settings.json"
  printf '~/ws/beta\n~/ws/beta-*\n' >"$BOARD_RESOURCES_HOME/beta/roots"
  printf '{"permissions":{"deny":["Bash(board-ro *)"]}}\n' >"$BOARD_RESOURCES_HOME/beta/settings.json"
}

setup() { br_setup; }
