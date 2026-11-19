#!/usr/bin/env bats

load helper

@test "term_of: block IDs and 8 hex digits are rex, the rest is hc" {
  source "$SKILL_DIR/lib.sh"
  [ "$(term_of block:01a1ef15-4833-735e-9530-226d79648a16)" = rex ]
  [ "$(term_of 79648a16)" = rex ]
  [ "$(term_of t7)" = hc ]
}

@test "term_here: BOARD_TERM, then HC_TERMINAL_ID, then REX_BLOCK, else hc" {
  source "$SKILL_DIR/lib.sh"
  [ "$(term_here)" = hc ]
  [ "$(REX_BLOCK=block:x term_here)" = rex ]
  [ "$(HC_TERMINAL_ID=t1 REX_BLOCK=block:x term_here)" = hc ]
  [ "$(BOARD_TERM=rex HC_TERMINAL_ID=t1 term_here)" = rex ]
}

@test "term_tell_cmd on hc keeps the hc send line" {
  source "$SKILL_DIR/lib.sh"
  [ "$(HC_TERMINAL_ID=t3 term_tell_cmd 'report a /r.md')" = 'hc send t3 "report a /r.md"' ]
  [ "$(HC_TERMINAL_ID=t3 term_tell_rule)" = 'Bash(hc send t3 *)' ]
}
