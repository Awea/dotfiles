# shellcheck shell=bash
# The tests of herdr-app/bin reuse the helper and the fakes of the board orchestrator.
FAKES="$(cd "$BATS_TEST_DIRNAME/../../claude/skills/board-orchestrator/test" && pwd)"
# shellcheck source=SCRIPTDIR/../../claude/skills/board-orchestrator/test/helper.bash
source "$FAKES/helper.bash"
# shellcheck disable=SC2034 # Used by the test files.
AT="$BATS_TEST_DIRNAME/../bin/agent-tabs.sh"
