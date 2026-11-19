# scan.awk: the command scan of guard.sh. It reads a shell command on stdin and prints
# the reason to block it, or nothing. POSIX awk only: it runs with the awk of macOS, gawk
# and mawk. -v sess=SESSION: the Rex session of the worker. -v sessfree=1: the command
# does not set REX_SESSION, so the text $REX_SESSION is the session of the worker.
#
# The scan follows the quotes of the shell: a quoted ; & | or newline does not split a
# command. A $( ), a ` `, a ( ), an unquoted heredoc body, a shell -c TEXT, an eval and a
# heredoc fed to a shell hold commands. A quoted heredoc body, a comment, an arithmetic
# $(( )) and the target of a redirection hold none.
#
# Speed: each text goes once into the array G, one char for each element, so a read of a
# char takes a constant time. A substr in the awk of macOS counts the chars of the whole
# string, and a scan with substr takes a time that grows with the square of the size.
#
# The state: G the chars, GN their number. The text of the scan is G[B + 1] to G[B + L],
# P the position in it (from 1). W the word (at most 4096 chars), WLEN its length, IW 1
# when the word has a quote, SK 1 when the next word is the target of a redirection, WST
# the position of the start of the word, 0 before a word. seg[i] is the word i of a
# simple command after quote removal, and seg["s", i] to seg["e", i] its text in G before
# quote removal. DEPTH the level of the text: HD[DEPTH, i] its pending heredocs,
# NH[DEPTH] their number, LS[DEPTH] 1 when its line has a shell.

{ cmd = cmd (NR > 1 ? "\n" : "") $0 }

END { scan_text(cmd) }

function blk(reason) {
  print reason
  exit
}

# arg(seg, i): the word i of the command, or "".
function arg(seg, i) { return i <= seg["n"] ? seg[i] : "" }

function base(w) {
  sub(/.*\//, "", w)
  return w
}

# at(i): the char i of the text, or "" out of the text.
function at(i) { return (i >= 1 && i <= L) ? G[B + i] : "" }

# gtext(s, e): the chars G[s] to G[e - 1], at most 4096.
function gtext(s, e,   t, i) {
  t = ""
  if (e - s > 4096) e = s + 4096
  for (i = s; i < e; i++) t = t G[i]
  return t
}

# addw(x): add x to the word. A word longer than 4096 chars is not a command name or an
# option, so the end of a long word is not kept.
function addw(x) {
  if (WLEN < 4096) {
    W = W x
    WLEN += length(x)
  }
}

# scan_text(t): put the text t in G and scan its commands.
function scan_text(t,   n, tmp, i, b) {
  n = split(t, tmp, "")
  b = GN
  for (i = 1; i <= n; i++) G[b + i] = tmp[i]
  GN += n
  scan_range(b, n, 1)
}

# scan_range(b, n, cmds): scan the n chars after G[b]: its commands when cmds is 1, else
# only its $( ) and ` ` (the body of an unquoted heredoc).
function scan_range(b, n, cmds,   sB, sP, sL, sw, swl) {
  sB = B; sP = P; sL = L; sw = W; swl = WLEN
  B = b; P = 1; L = n
  DEPTH++
  NH[DEPTH] = 0; LS[DEPTH] = 0
  if (cmds) sub_cmd("")
  else scan_body()
  DEPTH--
  B = sB; P = sP; L = sL; W = sw; WLEN = swl
}

# sub_cmd(end): scan the commands up to end with a new word, then go back to the word.
function sub_cmd(end,   sw, swl, siw, ssk, swst) {
  sw = W; swl = WLEN; siw = IW; ssk = SK; swst = WST
  W = ""; WLEN = 0; IW = 0; SK = 0; WST = 0
  scan_cmd(end)
  W = sw; WLEN = swl; IW = siw; SK = ssk; WST = swst
}

# scan_cmd(end): scan the commands from P up to end: ")", "`" or "" for the end of the
# text.
function scan_cmd(end,   c, n, seg) {
  seg["n"] = 0
  while (P <= L) {
    c = G[B + P]
    if (!WST && index(" \t\n;&|()<>", c) == 0) WST = P
    if (c == " " || c == "\t") {
      flush(seg); P++
    } else if (c == "\n") {
      flush(seg); end_seg(seg); P++
      read_heredocs()
    } else if (c == ";" || c == "&" || c == "|") {
      flush(seg); end_seg(seg); P++
    } else if (c == "(") {
      flush(seg); end_seg(seg)
      # An arithmetic (( )) command.
      if (at(P + 1) == "(") { P += 2; skip_arith() }
      else { P++; sub_cmd(")") }
    } else if (c == ")") {
      flush(seg); end_seg(seg); P++
      if (end == ")") return
    } else if (c == "`") {
      P++
      if (end == "`") { flush(seg); end_seg(seg); return }
      sub_cmd("`"); IW = 1
    } else if (c == "'") {
      P++
      while (P <= L && G[B + P] != "'") { addw(G[B + P]); P++ }
      IW = 1; P++
    } else if (c == "\"") {
      P++; IW = 1
      scan_dq()
    } else if (c == "\\") {
      n = at(P + 1)
      if (n != "\n") { addw(n); IW = 1 }
      P += 2
    } else if (c == "$") {
      IW = 1
      if (at(P + 1) == "'") {
        P += 2
        while (P <= L && (n = G[B + P]) != "'") {
          if (n == "\\") { addw(n); P++; n = at(P) }
          addw(n); P++
        }
        P++
      } else scan_dollar()
    } else if (c == "#") {
      # A comment starts only at the start of a word.
      if (W == "" && !IW) { while (P <= L && G[B + P] != "\n") P++ }
      else { addw(c); P++ }
    } else if (c == "<" && at(P + 1) == "<" && at(P + 2) == "<") {
      flush(seg); P += 3; SK = 1
    } else if (c == "<" && at(P + 1) == "<") {
      flush(seg); P += 2
      heredoc_word()
    } else if (c == "<" || c == ">") {
      # A file descriptor number before the operator is not a word.
      if (!IW && W ~ /^[0-9]+$/) { W = ""; WLEN = 0 }
      flush(seg); P++
      while (P <= L && index("<>&|", G[B + P]) > 0) P++
      SK = 1
    } else {
      addw(c); P++
    }
  }
  flush(seg); end_seg(seg)
}

# flush(seg): end the word. The word after a redirection is its target, not a word.
function flush(seg,   n) {
  if (W != "" || IW) {
    if (SK) SK = 0
    else {
      n = ++seg["n"]
      seg[n] = W
      seg["s", n] = B + WST
      seg["e", n] = B + P
    }
  }
  W = ""; WLEN = 0; IW = 0; WST = 0
}

# end_seg(seg): end the simple command and check it.
function end_seg(seg) {
  if (seg["n"] > 0) check_words(seg)
  split("", seg)
  seg["n"] = 0; SK = 0
}

# scan_dq(): scan a double-quoted text from P up to its end quote. Only $( ) and ` `
# hold commands in it.
function scan_dq(   c, n) {
  while (P <= L) {
    c = G[B + P]
    if (c == "\"") { P++; return }
    if (c == "\\") {
      n = at(P + 1)
      if (n == "$" || n == "`" || n == "\"" || n == "\\") addw(n)
      else if (n != "\n") addw(c n)
      P += 2
    } else if (c == "$") {
      scan_dollar()
    } else if (c == "`") {
      P++; sub_cmd("`")
    } else {
      addw(c); P++
    }
  }
}

# scan_dollar(): scan the $ at P. A $( ) holds commands. A $(( )) and a ${ } are parts
# of the word.
function scan_dollar(   n) {
  n = at(P + 1)
  if (n == "(" && at(P + 2) == "(") { P += 3; skip_arith(); addw("$(())") }
  else if (n == "(") { P += 2; sub_cmd(")"); addw("$()") }
  else if (n == "{") { P += 2; addw("${"); scan_brace() }
  else { addw("$"); P++ }
}

# skip_arith(): skip an arithmetic text from P up to its )). A << in it is a shift.
function skip_arith(   depth, c) {
  depth = 2
  while (P <= L && depth > 0) {
    c = G[B + P]
    if (c == "(") depth++
    else if (c == ")") depth--
    P++
  }
}

# scan_brace(): scan a ${ } from P up to its }. A # or a space in it is a part of the word.
function scan_brace(   c) {
  while (P <= L) {
    c = G[B + P]
    if (c == "}") { addw(c); P++; return }
    if (c == "\\") { addw(at(P + 1)); P += 2 }
    else if (c == "'") {
      P++
      while (P <= L && G[B + P] != "'") { addw(G[B + P]); P++ }
      P++
    } else if (c == "\"") { P++; scan_dq() }
    else if (c == "$") scan_dollar()
    else if (c == "`") { P++; sub_cmd("`") }
    else { addw(c); P++ }
  }
}

# heredoc_word(): read the delimiter word after << or <<-, and keep it for the body. A
# quote in the word makes a quoted heredoc: its body has no expansion.
function heredoc_word(   strip, quoted, delim, c) {
  strip = "_"; quoted = "_"; delim = ""
  if (at(P) == "-") { strip = "-"; P++ }
  while (P <= L && index(" \t", G[B + P]) > 0) P++
  while (P <= L) {
    c = G[B + P]
    if (index(" \t\n;&|<>()", c) > 0) break
    if (c == "'" || c == "\"") quoted = "q"
    else if (c == "\\") { quoted = "q"; P++; delim = delim at(P) }
    else delim = delim c
    P++
  }
  HD[DEPTH, ++NH[DEPTH]] = strip quoted delim
}

# read_heredocs(): after a newline, skip the body of each heredoc of the line. The body
# of a heredoc fed to a shell is a script. The body of another unquoted heredoc can hold
# a $( ) or a ` `.
function read_heredocs(   n, i, h, shell, list, delim, dl, st, k, bst, bend) {
  n = NH[DEPTH]; shell = LS[DEPTH]
  for (i = 1; i <= n; i++) list[i] = HD[DEPTH, i]
  NH[DEPTH] = 0; LS[DEPTH] = 0
  for (i = 1; i <= n; i++) {
    h = list[i]
    delim = substr(h, 3); dl = length(delim)
    bst = P; bend = L + 1
    while (P <= L) {
      st = P
      while (P <= L && G[B + P] != "\n") P++
      # The line is st to P - 1. <<- removes its leading tabs.
      k = st
      if (substr(h, 1, 1) == "-") while (k < P && G[B + k] == "\t") k++
      if (P - k == dl && gtext(B + k, B + P) == delim) { bend = st; P++; break }
      P++
    }
    if (shell) scan_range(B + bst - 1, bend - bst, 1)
    else if (substr(h, 2, 1) != "q" && has_sub(bst, bend)) scan_range(B + bst - 1, bend - bst, 0)
  }
}

# has_sub(s, e): 1 when the chars s to e - 1 of the text hold a $( or a `.
function has_sub(s, e,   k, c) {
  for (k = s; k < e; k++) {
    c = G[B + k]
    if (c == "`" || (c == "$" && k + 1 < e && G[B + k + 1] == "(")) return 1
  }
  return 0
}

# scan_body(): scan the $( ) and ` ` of the body of an unquoted heredoc.
function scan_body(   c) {
  while (P <= L) {
    c = G[B + P]
    W = ""; WLEN = 0
    if (c == "$") scan_dollar()
    else if (c == "`") { P++; sub_cmd("`") }
    else if (c == "\\") P += 2
    else P++
  }
}

# check_words(seg): check one simple command, with its words after quote removal. The
# command word is the first one after the VAR=value words, the prefix words (do, time,
# xargs...) and the options of a prefix. eval runs its words as a command.
function check_words(seg,   n, j, k, w, p) {
  n = seg["n"]
  # A shell anywhere in the command (timeout 10 bash -c, find -exec sh -c) runs the
  # text after its -c.
  for (k = 1; k <= n; k++) {
    p = base(seg[k])
    if (p == "bash" || p == "sh" || p == "zsh" || p == "dash") shell_at(seg, k)
  }
  j = 1
  while (j <= n) {
    w = seg[j]
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { j++; continue }
    p = base(w)
    if (index(" do then else elif if while until ! { command exec ", " " p " ") > 0 && p !~ / /) {
      j++
    } else if (index(" time env nohup xargs sudo nice timeout when-free ", " " p " ") > 0 && p !~ / /) {
      j++
      while (j <= n && seg[j] ~ /^-./) {
        w = seg[j]
        if ((p == "xargs" && w ~ /^-[ILnPdsEa]$/) || (p == "env" && w ~ /^-[uCS]$/) ||
            (p == "sudo" && w ~ /^-[ugChpUrtD]$/) || (p == "nice" && w == "-n") ||
            (p == "timeout" && w ~ /^-[sk]$/)) j += 2
        else j++
      }
      # The duration of timeout.
      if (p == "timeout") j++
    } else break
  }
  if (j > n) return
  p = base(seg[j])
  if (p == "eval") {
    w = ""
    for (k = j + 1; k <= n; k++) w = w (k > j + 1 ? " " : "") seg[k]
    scan_text(w)
  } else if (p == "rex") rex_check(seg, j)
}

# shell_at(seg, k): the word k is a shell. Scan the text after its -c. A shell with no -c
# reads its commands from its input: a heredoc of the line holds commands.
function shell_at(seg, k,   i, w) {
  for (i = k + 1; i <= seg["n"]; i++) {
    w = seg[i]
    if (w ~ /^--/) continue
    if (w ~ /^-.*c/) { scan_text(arg(seg, i + 1)); return }
    # -o and -O take the next word, also at the end of a group such as -euo.
    if (w ~ /^[-+].*[oO]$/) { i++; continue }
    if (w ~ /^[-+]/) continue
    break
  }
  LS[DEPTH] = 1
}

# rex_check(seg, j): block a rex call (the word j) that changes the Renux window. A read
# (ls, wait, capture, help, --help, a read of the API) stays free. A --help after --
# belongs to the program that rex starts. rex block close stays free, so that the worker
# can close its job tab: the guard cannot tell who started a block.
function rex_check(seg, j,   i, sub1, a3, a4) {
  for (i = j + 1; i <= seg["n"]; i++) {
    if (seg[i] == "--") break
    if (seg[i] == "--help") return
  }
  sub1 = arg(seg, j + 1); a3 = arg(seg, j + 2); a4 = arg(seg, j + 3)
  if (index(" capture help --help version keymap ls list wait whoami events actions ", " " sub1 " ") > 0 && sub1 !~ / /) return
  if (sub1 == "run") {
    if (job_tab(seg, j + 2)) return
  } else if (sub1 == "block") {
    if (a3 == "close") return
    sub1 = "block " a3
  } else if (sub1 == "server") {
    if (a3 == "status") return
    sub1 = "server " a3
  } else if (sub1 == "api" && a3 == "call") {
    if (index(" session.list session.list_blocks session.view session.describe_block target.resolve help.all session.help " \
      "com.superlogical.terminal.title com.superlogical.terminal.process com.superlogical.terminal.program_status " \
      "com.superlogical.terminal.pwd com.superlogical.terminal.size com.superlogical.terminal.shell ", " " a4 " ") > 0 && a4 !~ / / && a4 != "") return
    sub1 = "api call " a4
  }
  blk("change the Renux window (rex" (sub1 != "" ? " " sub1 : "") ")")
}

# job_tab(seg, k): 1 when the words from k are the options of a job tab: rex run
# --focus=false, with no session or the session of the worker, and only the options of a
# job tab (no --split, --block or --window). An option with a value takes the next word,
# as the program does. Each value is a word that the shell does not change. The words
# after -- are the command of the tab: the guard checks them too.
function job_tab(seg, k,   n, i, r, take, focus, own, bad, ended, tab) {
  n = seg["n"]; own = 1; take = ""; focus = 0; bad = 0; ended = 0
  for (i = k; i <= n; i++) {
    r = gtext(seg["s", i], seg["e", i])
    if (take == "session") { if (!own_session(r)) own = 0; take = ""; continue }
    if (take == "value") { if (!value_ok(r)) bad = 1; take = ""; continue }
    if (r == "--") { ended = i; break }
    if (r == "--focus=false") focus = 1
    else if (r == "--focus" || r ~ /^--focus=/) focus = 0
    else if (r == "-s" || r == "--session") take = "session"
    else if (r ~ /^--session=/) { if (!own_session(substr(r, 11))) own = 0 }
    else if (r == "-c" || r == "--cwd" || r == "--shell" || r == "--label") take = "value"
    else if (r ~ /^--(cwd|shell|label)=/) { if (!value_ok(substr(r, index(r, "=") + 1))) bad = 1 }
    else if (r != "--keep-open" && r != "--interactive" && r != "--json" && r != "--wait") bad = 1
  }
  if (!ended || !focus || !own || bad) return 0
  split("", tab)
  tab["n"] = 0
  for (i = ended + 1; i <= n; i++) {
    tab[++tab["n"]] = seg[i]
    tab["s", tab["n"]] = seg["s", i]
    tab["e", tab["n"]] = seg["e", i]
  }
  if (tab["n"] > 0) check_words(tab)
  return 1
}

# value_ok(r): 1 when the shell gives the text r as one word: a word of safe marks, or a
# word in one pair of quotes. A $( ) in a quoted word is a command of its own: the scan
# checks it.
function value_ok(r) {
  return r ~ "^[A-Za-z0-9_./:@+=,~-]+$" || r ~ "^\"([^\"\\\\]|\\\\.)*\"$" || r ~ "^'[^']*'$"
}

# own_session(r): 1 when the text r is the session of the worker. The text $REX_SESSION
# counts only when the command does not set REX_SESSION.
function own_session(r,   v) {
  if (r == "$REX_SESSION" || r == "\"$REX_SESSION\"") return sessfree + 0
  if (!value_ok(r)) return 0
  v = r
  sub(/^["']/, "", v)
  sub(/["']$/, "", v)
  return sess != "" && v == sess
}
