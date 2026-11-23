# shellcheck shell=bash disable=SC2154 # here: set by dispatch.sh.
# The board triage functions of dispatch.sh: the card-count trigger (triage-check), the
# apply of the approved changes (triage-apply) and the permissions of a triage worker.
# dispatch.sh sources this file after lib.sh, and sets here (the skill folder).

# The limit of open cards when the board frontmatter has no triage-limit.
TRIAGE_LIMIT=100
# The days between two offers of a triage of the same board.
TRIAGE_COOLDOWN_DAYS=14

# triage_state_file BOARD: the file that keeps the last offer or start of a triage of
# BOARD, one line "EPOCH YYYY-MM-DD".
triage_state_file() { printf '%s/triage/%s\n' "$(state_dir)" "$(board_slug "$1")"; }

# triage_mark BOARD: write now as the last offer or start of a triage of BOARD.
triage_mark() {
  local f
  f=$(triage_state_file "$1")
  mkdir -p "$(dirname "$f")"
  printf '%s %s\n' "$(date +%s)" "$(date +%F)" >"$f"
}

# triage_check BOARD: print whether a triage of BOARD is due. Due: more open cards than
# the limit, and no offer in the last TRIAGE_COOLDOWN_DAYS days. A due check marks the
# offer. Exit 2 when board-scan fails (its stderr tells why).
triage_check() {
  local board=$1 vault scan open limit f epoch day last=""
  scan=$(bash "$here/board-scan.sh" cards "$board" 2>/dev/null) ||
    { bash "$here/board-scan.sh" cards "$board" >/dev/null; return 2; }
  # The last line is the summary. A checked card in an open column is not open.
  open=$(sed '$d' <<<"$scan" | jq -s '[.[] | select(.checked | not)] | length')
  vault=$(vault_path)
  limit=$(fm triage-limit "$vault/Boards/$board.md")
  [[ "$limit" =~ ^[1-9][0-9]*$ ]] || limit=$TRIAGE_LIMIT
  f=$(triage_state_file "$board")
  if [ -f "$f" ] && read -r epoch day <"$f" && [[ "$epoch" =~ ^[0-9]+$ ]] &&
    [ $(($(date +%s) - epoch)) -lt $((TRIAGE_COOLDOWN_DAYS * 86400)) ]; then
    last=", last $day"
  fi
  if [ "$open" -gt "$limit" ] && [ -z "$last" ]; then
    triage_mark "$board"
    printf 'triage: due %s open cards, limit %s\n' "$open" "$limit"
  else
    printf 'triage: not due, %s open cards, limit %s%s\n' "$open" "$limit" "$last"
  fi
}

# triage_block REPORT: print the lines of the first ```jsonl block under the heading
# ## Vault changes of REPORT. Exit 1 when there is no such block.
triage_block() {
  # The block can be indented in a list item: the indent of its fence is cut from each line.
  awk 'f && /^[ \t]*```[ \t]*$/ { found = 1; exit }
    f { if (substr($0, 1, length(ind)) == ind) $0 = substr($0, length(ind) + 1); print; next }
    /^## / { v = ($0 ~ /^## Vault changes[ \t]*$/); next }
    v && /^[ \t]*```jsonl[ \t]*$/ { f = 1; ind = $0; sub(/[^ \t].*$/, "", ind) }
    END { exit !found }' "$1"
}

# triage_report_id REPORT: the checksum and size of REPORT: a new report text gives a new ID.
triage_report_id() { cksum <"$1" | awk '{ print $1 "-" $2 }'; }

# triage_applied REPORT: exit 0 when triage-apply applied this text of REPORT already.
triage_applied() {
  local f
  f="$(state_dir)/triage/applied"
  [ -f "$1" ] && [ -f "$f" ] && grep -qxF "$(triage_report_id "$1") $1" "$f"
}

# triage_mark_applied REPORT: remember that triage-apply applied this text of REPORT.
triage_mark_applied() {
  mkdir -p "$(state_dir)/triage"
  printf '%s %s\n' "$(triage_report_id "$1")" "$1" >>"$(state_dir)/triage/applied"
}

# triage_records: read the jsonl lines on stdin, and print one record for each change:
# OP, TITLE_LINE, CONTEXT_LINE, NEW and "." (so that an empty NEW stays a field), each
# with \x1f after it, then \x1e. A line that is not a valid change: the reason on stderr
# and exit 2. An empty line is skipped.
triage_records() {
  local n=0 line
  # shellcheck disable=SC2016 # A jq program.
  local valid='type == "object"
    and (.op | IN("done", "delete", "context", "title"))
    and (.title_line | type == "string" and test("^- \\[.\\] ") and (contains("\n") | not))
    and (.context_line | type == "string")
    and (.new == null or (.new | type == "string" and (contains("\n") | not)))
    and (if .op == "context" then (.new // "") != ""
         elif .op == "title" then (.new // "" | test("^- \\[ \\] "))
         else true end)'
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -n "${line//[[:space:]]/}" ] || continue
    if ! jq -e "$valid" <<<"$line" >/dev/null 2>&1; then
      printf 'triage-apply: line %d of the jsonl block is not a valid change: %s\n' "$n" "$line" >&2
      return 2
    fi
    jq -j '[.op, .title_line, .context_line, (.new // ""), "."] | map(. + "\u001f") | add + "\u001e"' <<<"$line"
  done
}

# triage_live_addrs BOARD: the short address (8 hex digits) of each worker of BOARD in the
# workers file, one for each line.
triage_live_addrs() {
  local f
  f=$(workers_file)
  [ -f "$f" ] || return 0
  awk -F '\t' -v b="$1" '$3 == b { a = $1; sub(/^block:/, "", a); print substr(a, 1, 8) }' "$f"
}

# triage_apply BOARD REPORT: apply the changes of the jsonl block of REPORT to the board
# file of BOARD, in one write. Each change names its card by its exact title and context
# lines, in an open column. Print "triage-apply: applied N of M", then one "skipped:" line
# for each change that did not apply. Exit 1 when the board changed during the run
# (nothing written), 2 for a missing board, no block or a bad line.
triage_apply() {
  local board=$1 report=$2 vault="" file block records msgs out rc=0
  vault=$(vault_path) || true
  file="$vault/Boards/$board.md"
  if [ -z "$vault" ] || [ ! -f "$file" ]; then
    printf 'triage-apply: no board %s in the vault.\n' "$board" >&2
    return 2
  fi
  if triage_applied "$report"; then
    echo 'triage-apply: applied already'
    return 0
  fi
  if [ ! -f "$report" ] || ! block=$(triage_block "$report"); then
    printf 'triage-apply: %s has no jsonl block under ## Vault changes.\n' "$report" >&2
    return 2
  fi
  records=$(mktemp) msgs=$(mktemp) out=$(mktemp)
  triage_apply_run "$board" "$file" "$vault" "$block" "$records" "$msgs" "$out" || rc=$?
  rm -f "$records" "$msgs" "$out"
  [ "$rc" -ne 0 ] || triage_mark_applied "$report"
  return "$rc"
}

# triage_apply_run BOARD FILE VAULT BLOCK RECORDS MSGS OUT: the work of triage_apply, with
# its temp files.
triage_apply_run() {
  local board=$1 file=$2 vault=$3 block=$4 records=$5 msgs=$6 out=$7 before after tmp iso md day
  triage_records <<<"$block" >"$records" || return 2
  before=$(cksum <"$file")
  iso=$(date +%F)
  day=$(date +%d)
  md="$(LC_ALL=C date +%b) $((10#$day))"
  awk -v chf="$records" -v msgf="$msgs" -v outf="$out" -v iso="$iso" -v md="$md" \
    -v live="$(triage_live_addrs "$board" | tr '\n' ' ')" '
    BEGIN {
      RS = "\036"
      while ((getline rec < chf) > 0) {
        m++; split(rec, a, "\037"); op[m] = a[1]; T[m] = a[2]; C[m] = a[3]; N[m] = a[4]
      }
      close(chf)
      RS = "\n"
      split("📥 Backlog|📋 This Week|🔨 In Progress|⏳ Waiting On", oc, "|")
      for (i in oc) open[oc[i]] = 1
      nl = split(live, addrs, " ")
    }
    { L[NR] = $0 }
    END {
      n = NR
      for (i = 1; i <= n; i++) {
        if (L[i] ~ /^## /) { col = substr(L[i], 4); sub(/[ \t\r]+$/, "", col); if (col == "✅ Done") dh = i; continue }
        if (dh && dh < i && top == "" && L[i] ~ /^- \[.\] /) top = L[i]
        if (!(col in open) || L[i] !~ /^- \[.\] /) continue
        e = i; ctx = ""
        while (e < n && L[e + 1] ~ /^\t/) { e++; ctx = (ctx == "" ? L[e] : ctx "\n" L[e]) }
        k = L[i] "\034" ctx
        count[k]++; start[k] = i; stop[k] = e
      }
      date = iso
      if (top ~ /✅ [A-Z][a-z][a-z] [0-9]/) date = md
      strike = (top ~ /~~/)
      applied = 0; skips = ""
      for (j = 1; j <= m; j++) {
        k = T[j] "\034" C[j]; why = ""
        if (!(k in count)) why = "not found"
        else if (count[k] > 1) why = "found twice"
        else if (k in used) why = "changed by an earlier change"
        else if (op[j] == "done" && !dh) why = "no Done column"
        else for (x = 1; x <= nl; x++) if (addrs[x] != "" && index(C[j], addrs[x])) { why = "live worker " addrs[x]; break }
        if (why != "") { skips = skips "skipped: " T[j] " — " why "\n"; continue }
        used[k] = 1; applied++
        s = start[k]; e = stop[k]
        for (x = s; x <= e; x++) del[x] = 1
        if (op[j] == "context") rep[s] = T[j] "\n\t" N[j]
        else if (op[j] == "title") rep[s] = N[j] (C[j] == "" ? "" : "\n" C[j])
        else if (op[j] == "done") {
          t = T[j]; sub(/^- \[.\] /, "", t); sub(/[ \t]+$/, "", t)
          if (strike) t = "~~" t "~~"
          card = "- [x] " t " ✅ " date
          c = (N[j] != "" ? "\t" N[j] : C[j])
          if (c != "") card = card "\n" c
          donetext = (donetext == "" ? card : card "\n" donetext)
        }
      }
      printf "triage-apply: applied %d of %d\n%s", applied, m, skips > msgf
      if (!applied) exit
      for (i = 1; i <= n; i++) {
        if (i in rep) print rep[i] > outf
        else if (!(i in del)) print L[i] > outf
        if (i == dh && donetext != "") {
          if (i < n && L[i + 1] ~ /^[ \t\r]*$/) { i++; print L[i] > outf }
          print donetext > outf
        }
      }
    }' "$file"
  [ -z "${TRIAGE_APPLY_TEST_HOOK:-}" ] || eval "$TRIAGE_APPLY_TEST_HOOK"
  after=$(cksum <"$file")
  if [ "$before" != "$after" ]; then
    printf 'triage-apply: the board changed during the run. Nothing written.\n'
    return 1
  fi
  if [ -s "$out" ]; then
    # cp -p keeps the mode of the board. The rename writes the board at once.
    if ! { tmp=$(mktemp "$vault/Boards/.$board.md.XXXXXX") && cp -p "$file" "$tmp" &&
      cat "$out" >"$tmp" && mv "$tmp" "$file"; } 2>/dev/null; then
      rm -f "${tmp:-}"
      printf 'triage-apply: could not write the board %s. Nothing written.\n' "$file" >&2
      return 1
    fi
  fi
  cat "$msgs"
}

# The read calls of a triage worker. The repos and the state folder get a Read rule each.
TRIAGE_ALLOW=('Bash(gh pr view*)' 'Bash(gh pr list*)' 'Bash(gh issue view*)' 'Bash(gh issue list*)'
  'Bash(git -C * fetch*)' 'Bash(git -C * log*)' 'Bash(git -C * show*)' 'Bash(git -C * merge-base*)'
  'Bash(git -C * ls-remote*)' 'Bash(git -C * worktree list*)' 'Bash(git -C * branch -r*)'
  'Bash(git -C * grep*)' 'Bash(git -C * rev-parse*)')
# The calls that a triage worker never makes, on top of the push, forge and merge rules of
# dispatch.sh. The vault and the repos get an Edit rule each. A deny rule wins over an
# allow rule, also over an allow rule of the board.
TRIAGE_DENY=('Bash(gh api*)' 'Bash(board-ro*)' 'Bash(ssh*)' 'Bash(mosh*)'
  'Bash(gh pr review*)' 'Bash(gh pr reopen*)' 'Bash(gh issue close*)' 'Bash(gh issue reopen*)'
  'Bash(gh issue delete*)' 'Bash(gh release*)' 'Bash(gh workflow*)' 'Bash(gh run*)' 'Bash(gh label*)'
  'Bash(tea*)'
  # A * in the middle of an allow rule takes any later word: 'git -C * log*' also takes
  # 'git -C repo branch -D login'. So the git writes get a deny rule each.
  'Bash(git -C * branch -d*)' 'Bash(git -C * branch -D*)' 'Bash(git -C * branch -m*)'
  'Bash(git -C * reset*)' 'Bash(git -C * checkout*)' 'Bash(git -C * switch*)' 'Bash(git -C * restore*)'
  'Bash(git -C * clean*)' 'Bash(git -C * stash*)' 'Bash(git -C * commit*)' 'Bash(git -C * rebase*)'
  'Bash(git -C * merge *)' 'Bash(git -C * tag -d*)' 'Bash(git -C * update-ref*)' 'Bash(git -C * rm *)'
  'Bash(git -C * worktree remove*)' 'Bash(git -C * worktree prune*)' 'Bash(git -C * gc*)')

# triage_settings BOARD VAULT: the settings JSON of a triage worker of BOARD: its allow
# and deny rules.
triage_settings() {
  local repo
  local -a allow=("${TRIAGE_ALLOW[@]}" "Read(/$(state_dir)/**)")
  local -a deny=("${GIT_PUSH_RULES[@]}" "${GH_FORGE_RULES[@]}" "${GH_MERGE_RULES[@]}"
    "${FORGEJO_FORGE_RULES[@]}" "${TRIAGE_DENY[@]}" "Edit(/$2/**)")
  while IFS= read -r repo; do
    allow+=("Read(/$repo/**)")
    deny+=("Edit(/$repo/**)")
  done < <(other_tops "$1" "$2")
  jq -cn --args '{permissions: {allow: $ARGS.positional[:($n | tonumber)], deny: $ARGS.positional[($n | tonumber):]}}' \
    --arg n "${#allow[@]}" "${allow[@]}" "${deny[@]}"
}
