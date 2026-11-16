#!/usr/bin/env bats
# The herdr-app mods: the checks that need no window.

load helper

@test "the ask.js copies of the popup mods are the same" {
  cd "$BATS_TEST_DIRNAME/../mods"
  cmp new-agent-tab/ask.js handoff/ask.js
  cmp new-agent-tab/ask.js new-space/ask.js
}

@test "no mod posts a notification or plays a sound" {
  # cx.notify() only redraws a mod: look for the notify and playSound of "herdr".
  ! grep -rn -E '(^|[^.?[:alnum:]_])notify\(|playSound|import \{[^}]*\bnotify\b' \
    "$BATS_TEST_DIRNAME/../mods" --include=main.js --include=ask.js
}

@test "quiet-toast closes every toast, an error too" {
  # A toast mod that draws nothing and checks no level shows no toast.
  ! grep -n -E 'level|on_click|timer' "$BATS_TEST_DIRNAME/../mods/quiet-toast/main.js"
}

@test "the main-quiet layout starts the claude-resume mod in a block that is always shown" {
  # A mod starts the first time its block shows: the work column is never hidden.
  jq -e '.. | objects | select(.id == "work") | .children[]
    | select(.content.mod == "claude-resume") | (.hidden // false) == false' \
    "$BATS_TEST_DIRNAME/../layouts/main-quiet.json"
}

@test "make herdr-app links the claude-resume mod" {
  grep -E '^\s*for m in .*\bclaude-resume\b' "$BATS_TEST_DIRNAME/../../Makefile"
}

@test "the claude-resume mod runs claude-resume.sh tick again and again, never in a check" {
  local m="$BATS_TEST_DIRNAME/../mods/claude-resume/main.js"
  grep -F 'bin/claude-resume.sh' "$m"
  grep -F '"tick"' "$m"
  grep -F 'cx.sleep(' "$m"
  # herdr-app check runs init for real: a check must not resume a live terminal.
  grep -E 'if \(checking\(\)\) return;' "$m"
}

@test "no Claude hook is necessary: the settings do not run claude-session.sh" {
  ! grep -F 'claude-session' "$BATS_TEST_DIRNAME/../../claude/settings.json"
}

@test "new-space binds Tab to its own action, since the app takes Tab before keys.json" {
  # Tab is an app action (focus the next field): on_key_down and a keys.json mod
  # section never see it. A cx.bind_keys binding under the popup key context comes first.
  local m="$BATS_TEST_DIRNAME/../mods/new-space/main.js"
  grep -q 'keystroke: "tab", action: "new_space_claude"' "$m"
  grep -q 'on_action("new_space_claude"' "$m"
  ! jq -e '."mod:new-space".tab' "$BATS_TEST_DIRNAME/../keys.json"
}
