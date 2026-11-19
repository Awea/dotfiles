# shellcheck shell=bash
# The tests of config/rex/bin reuse the helper and the fakes of the board orchestrator.
FAKES="$(cd "$BATS_TEST_DIRNAME/../../../claude/skills/board-orchestrator/test" && pwd)"
# shellcheck source=SCRIPTDIR/../../../claude/skills/board-orchestrator/test/helper.bash
source "$FAKES/helper.bash"
# shellcheck disable=SC2034 # Used by the test files.
BIN="$BATS_TEST_DIRNAME/../bin"
# The helper above finds the skill folder from the test folder: point it at the skill.
# shellcheck disable=SC2034 # Used by fake_block.
SKILL_DIR="$(cd "$FAKES/.." && pwd)"
