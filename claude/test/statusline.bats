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

@test "the percent is green below 50, yellow below 80, red from 80" {
  for p in 10:32 60:33 85:31; do
    out=$(bash "$SCRIPT" <<<"{\"context_window\":{\"context_window_size\":100000,
      \"used_percentage\":${p%%:*},\"current_usage\":null}}")
    [[ "$out" == *$'\e['"${p##*:}m"* ]] || return 1
  done
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
  [[ "$output" == "ctx 0k/200k "* ]]
}
