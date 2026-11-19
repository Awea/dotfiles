#!/usr/bin/env bash
# Claude Code status line: the context size of the session, for example "ctx 46k/200k 23%".
# Claude Code sends the session JSON on stdin. The used tokens are the input, cache write
# and cache read tokens of the last API call. The used tokens and the percent are green
# below 100k tokens, yellow to 150k and red over 150k, for each window size: past 150k
# the model gets worse. The thresholds use the rounded count of the line, so "150k" is
# yellow and "151k" is red. Before the first message, the line shows 0 tokens.
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
      | ($used / 1000 | round) as $k
      | (if $k < 100 then 32 elif $k <= 150 then 33 else 31 end) as $color
      | "ctx \u001b[\($color)m\($used | size)\u001b[0m/\($c.context_window_size | size) "
        + "\u001b[\($color)m\($pct)%\u001b[0m"
    end'
