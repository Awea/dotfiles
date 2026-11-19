#!/usr/bin/env bash
# Claude Code status line: the context size of the session, for example "ctx 46k/200k 23%".
# Claude Code sends the session JSON on stdin. The used tokens are the input, cache write
# and cache read tokens of the last API call. The percent is green below 50, yellow below
# 80 and red from 80. Before the first message, the line shows 0 tokens.
# Runs on Linux and macOS: it needs only bash and jq.
jq -r '
  def size: (. / 1000 | round) as $k
            | if $k >= 1000 then (($k / 100 | round) / 10 | tostring) + "M"
              else ($k | tostring) + "k" end;
  .context_window as $c
  | if ($c.context_window_size // null) == null then "ctx ?"
    else
      ($c.current_usage // {}) as $u
      | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
         + ($u.cache_read_input_tokens // 0)) as $used
      | ($c.used_percentage // 0 | round) as $pct
      | (if $pct < 50 then 32 elif $pct < 80 then 33 else 31 end) as $color
      | "ctx \($used | size)/\($c.context_window_size | size) "
        + "\u001b[\($color)m\($pct)%\u001b[0m"
    end'
