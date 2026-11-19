#!/usr/bin/env bats
# Tests for the Claude Code status line (claude/statusline.sh), its link and its setting.
# Run: ASDF_BATS_VERSION=1.8.2 bats claude/test/

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SCRIPT="$REPO/claude/statusline.sh"

# line JSON: the status line for the session JSON on stdin, with no color codes.
line() { bash "$SCRIPT" <<<"$1" | sed $'s/\x1b\\[[0-9;]*m//g'; }

@test "the status line shows the used tokens, the window size and the percent" {
  run line '{"context_window":{"context_window_size":200000,"used_percentage":23,
    "current_usage":{"input_tokens":5000,"output_tokens":800,
    "cache_creation_input_tokens":1000,"cache_read_input_tokens":40000}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 46k/200k 23%" ]
}

@test "the status line shows a 1M window" {
  run line '{"context_window":{"context_window_size":1000000,"used_percentage":12.6,
    "current_usage":{"input_tokens":126000,"output_tokens":0,
    "cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 126k/1M 13%" ]
}

@test "the status line rounds 999,600 tokens up to 1M, not 1000k" {
  run line '{"context_window":{"context_window_size":1000000,"used_percentage":99.96,
    "current_usage":{"input_tokens":999600}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 1M/1M 100%" ]
}

@test "the status line shows the window size before the first message" {
  run line '{"context_window":{"context_window_size":200000,"used_percentage":null,
    "current_usage":null}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 0k/200k 0%" ]
}

@test "the status line shows a line when Claude Code sends no context data" {
  run line '{"model":{"display_name":"Opus"}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx ?" ]
}

# color JSON: the color code before the used tokens, and before the percent.
color() {
  bash "$SCRIPT" <<<"$1" | sed -E $'s/^ctx \x1b\\[([0-9]+)m[^\x1b]*\x1b\\[0m\\/[^ ]* \x1b\\[([0-9]+)m.*/\\1 \\2/'
}

@test "the tokens and the percent are green below 100k, yellow to 150k, red over 150k" {
  for t in 50000:32 99400:32 99600:33 150000:33 150400:33 150600:31 400000:31; do
    run color "{\"context_window\":{\"context_window_size\":1000000,
      \"used_percentage\":10,\"current_usage\":{\"input_tokens\":${t%%:*}}}}"
    [ "$output" = "${t##*:} ${t##*:}" ] || { echo "${t%%:*}: $output"; return 1; }
  done
}

@test "a 200k window uses the same token thresholds" {
  run color '{"context_window":{"context_window_size":200000,"used_percentage":78,
    "current_usage":{"input_tokens":155000}}}'
  [ "$output" = "31 31" ]
  run color '{"context_window":{"context_window_size":200000,"used_percentage":60,
    "current_usage":{"input_tokens":120000}}}'
  [ "$output" = "33 33" ]
}

@test "the status line is green before the first message" {
  run color '{"context_window":{"context_window_size":200000,"used_percentage":null,
    "current_usage":null}}'
  [ "$output" = "32 32" ]
}

@test "make links the status line script" {
  cd "$REPO"
  run make -n HOME="$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/.claude/statusline.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s $REPO/claude/statusline.sh $BATS_TEST_TMPDIR/.claude/statusline.sh"* ]]
  grep -q '^links:.*\$(HOME)/\.claude/statusline\.sh' "$REPO/Makefile"
}

@test "the settings run the status line script and skip it when it is missing" {
  cmd=$(jq -r '.statusLine.command' "$REPO/claude/settings.json")
  [ "$(jq -r '.statusLine.type' "$REPO/claude/settings.json")" = command ]
  [[ "$cmd" == *'$HOME/.claude/statusline.sh'* ]]
  run env HOME="$BATS_TEST_TMPDIR" sh -c "$cmd" <<<'{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  ln -s "$SCRIPT" "$BATS_TEST_TMPDIR/.claude/statusline.sh"
  run env HOME="$BATS_TEST_TMPDIR" sh -c "$cmd" <<<'{"context_window":{"context_window_size":200000}}'
  [ "$status" -eq 0 ]
  [[ "$(sed $'s/\x1b\\[[0-9;]*m//g' <<<"$output")" == "ctx 0k/200k "* ]]
}
