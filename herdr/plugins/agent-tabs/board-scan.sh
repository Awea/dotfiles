#!/usr/bin/env bash
# Tool of the board orchestrator: read a vault board and its notes in one call. It only
# reads files.
#
#   board-scan.sh cards BOARD
#       Print one JSON object per line for each card of <vault>/Boards/BOARD.md in the
#       columns 📥 Backlog, 📋 This Week, 🔨 In Progress and ⏳ Waiting On: the exact
#       title and context lines, the card fields, the fields of its task note, the repo
#       of its project note, the push policy and the number of read-only rules of the
#       repo. Then print one line {"done": N, "board": BOARD, "today": YYYY-MM-DD}.
#       A context line longer than 200 characters has context_long true, and only its
#       first 200 characters show.
#       Exit 2 when there is no vault path, no such board, or no kanban-plugin line.
#   board-scan.sh card BOARD TEXT
#       Print the lines of cards for only the cards whose title has TEXT (a fixed text,
#       in any case), then the summary line of cards. The orchestrator uses it to check
#       one card just before an edit: the full output of cards is large. It gives the
#       full context line of a long card. The summary line
#       gives the board layout at that time, after the edits of the user.
#   board-scan.sh prompt TASK
#       Print the text of the first fenced code block under ## Prompt of the task note
#       TASK (relative to the vault, for example Tasks/X.md), without the fence lines.
#       The orchestrator reads only this block: the ## Runs section grows each run.
#       Exit 1 when the note has no prompt block. Exit 2 when there is no vault path or
#       no such note.
#   board-scan.sh inbox
#       Print one JSON object per line for each phone message in <vault>/_inbox (a
#       *.md file), oldest first: {file, text, truncated}.
#       FILE is relative to the vault. TEXT is cut at 2000 characters. Then print one
#       line {"inbox": N, "boards": {BOARD: [project notes of its cards]}}, so that the
#       orchestrator can tell which board a message goes to.
#   board-scan.sh rules
#       Print the sections of the vault _CLAUDE.md that the orchestrator follows:
#       Section 0, Frontmatter and Do Not Touch. Print nothing when there is no file.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

if ! vault=$(vault_path); then
  printf 'board-scan: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
  exit 2
fi

# Print the frontmatter value of key $1 in file $2: the text after "key:" in the block
# between the first two --- lines, trimmed, without surrounding quotes. Print nothing
# when the key is absent.
fm() {
  awk -v key="$1" '
    $0 == "---" { n++; if (n == 2) exit; next }
    n == 1 && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      gsub(/^[ \t]+|[ \t\r]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\x27.*\x27$/) v = substr(v, 2, length(v) - 2)
      print v
      exit
    }' "$2"
}

# Print the text of the first fenced code block under ## Prompt of file $1, before the
# next ## heading. Exit 1 when there is no such block.
prompt_block() {
  awk '/^## / && !f { p = ($0 ~ /^## Prompt[ \t]*$/); next }
    f && substr($0, 1, 3) == fence { exit }
    f { print; next }
    p && /^(```|~~~)/ { f = 1; fence = substr($0, 1, 3) }
    END { exit !f }' "$1"
}

case "${1:-}" in
  cards | card)
    board="${2:-}" match=""
    if [ "$1" = card ]; then
      match="${3:-}"
      if [ -z "$match" ]; then
        printf 'usage: board-scan.sh card BOARD TEXT\n' >&2
        exit 2
      fi
    fi
    file="$vault/Boards/$board.md"
    if [ -z "$board" ] || [ ! -f "$file" ]; then
      printf 'board-scan: no board %s in %s/Boards.\n' "$board" "$vault" >&2
      exit 2
    fi
    if ! grep -q '^kanban-plugin: board' "$file"; then
      printf 'board-scan: %s has no kanban-plugin: board line.\n' "$file" >&2
      exit 2
    fi
    today=$(date +%F)
    # The most characters of a context line (the orchestrator rule).
    context_max=200
    summary=()
    declare -A policies=() readonly_counts=()
    # One record for each card: column, line number, title line, context line.
    while IFS=$'\x1f' read -r -d $'\x1e' column line title_line context_line blank_flags other other_heads; do
      if [ "$column" = $'\x1d' ]; then
        # The summary record: done count, Done top title and context, blank flags,
        # other count, other headings.
        summary=("$line" "$title_line" "$context_line" "$blank_flags" "$other" "$other_heads")
        continue
      fi
      links="$title_line $context_line"
      task="" task_exists=false mode="" recurrence="" prompt=false
      project="" repo="" policy="" readonly=""
      if [[ "$links" =~ \[\[Tasks/([^]|#]+) ]]; then
        task="Tasks/${BASH_REMATCH[1]}.md"
        if [ -f "$vault/$task" ]; then
          task_exists=true
          mode=$(fm mode "$vault/$task")
          recurrence=$(fm recurrence "$vault/$task")
          if prompt_block "$vault/$task" >/dev/null; then
            prompt=true
          fi
        fi
      fi
      if [[ "$links" =~ \[\[Projects/([^]|#]+) ]]; then
        project="Projects/${BASH_REMATCH[1]}.md"
        if [ -f "$vault/$project" ]; then
          repo=$(fm repo "$vault/$project")
          [[ "$repo" != \~/* ]] || repo="$HOME/${repo#"~/"}"
          [ -z "$repo" ] || [ -d "$repo" ] || repo=""
        fi
      fi
      if [ -n "$repo" ]; then
        if [ -z "${policies[$repo]:-}" ]; then
          policies[$repo]=$(push_policy "$repo" 2>/dev/null) || policies[$repo]=invalid
          # read_settings gives one JSON object, or fails for an invalid file.
          readonly_counts[$repo]=$(read_settings "$repo/.claude/settings.readonly.json" 2>/dev/null |
            jq '[(.permissions | objects | .allow) // [] | arrays | .[] | strings | select(. != "")] | length' 2>/dev/null) ||
            readonly_counts[$repo]=0
          [[ "${readonly_counts[$repo]}" =~ ^[0-9]+$ ]] || readonly_counts[$repo]=0
        fi
        policy=${policies[$repo]}
        readonly=${readonly_counts[$repo]}
      fi
      jq -cn --arg column "$column" --argjson line "$line" --arg tl "$title_line" --arg cl "$context_line" \
        --arg today "$today" --arg task "$task" --argjson task_exists "$task_exists" --arg mode "$mode" \
        --arg recurrence "$recurrence" --argjson prompt "$prompt" --arg project "$project" --arg repo "$repo" \
        --arg policy "$policy" --arg readonly "$readonly" --arg match "$match" --argjson max "$context_max" '
        def n: if . == "" then null else . end;
        def after($re): ([match($re).captures[0].string] | first // null)
          | if . == null then null else sub("^\\s+"; "") | sub("\\s+$"; "") end;
        # The full scan goes into the orchestrator context: a long context line is cut
        # there. The scan of one card keeps it whole, as the old text of an edit.
        # The tab at the start of each line is not part of the text.
        ($cl | gsub("(^|\n)\t+"; "\n") | ltrimstr("\n") | length > $max) as $long
        | {column: $column, line: $line, title_line: $tl,
          context_line: (if $long and $match == "" then $cl[:$max] else $cl end), context_long: $long,
          checked: ($tl | test("^- \\[[xX]\\]")),
          priority: ($tl | [match("🔴|🟠|🟡|🟢").string][0] // null),
          recurring: ($tl | contains("🔁")),
          date: (if $tl | test("@\\{\\d{4}-\\d{2}-\\d{2}\\}") then ($tl | capture("@\\{(?<d>\\d{4}-\\d{2}-\\d{2})\\}").d) else null end),
          title: ($tl | [match("\\*\\*(.*?)\\*\\*").captures[0].string][0] // null),
          owner: ($tl + "\n" + $cl | after("owner:([^,·\n]*)") | n),
          waits: ($tl + "\n" + $cl | after("waits for([^,·\n]*)") | n),
          task: ($task | n), task_exists: $task_exists}
        | .due = (.date == null or .date <= $today)
        | if $task_exists then .mode = ($mode | n) | .recurrence = ($recurrence | n) | .prompt = $prompt else . end
        | .project = ($project | n) | .repo = ($repo | n)
        | if $repo != "" then .policy = $policy | .readonly = ($readonly | tonumber) else . end
        | select($match == "" or ((.title // "") | ascii_downcase | contains($match | ascii_downcase)))'
    done < <(awk '
      BEGIN {
        ncols = split("📥 Backlog|📋 This Week|🔨 In Progress|⏳ Waiting On|✅ Done", cols, "|")
        for (i = 1; i <= ncols; i++) known[cols[i]] = i
      }
      function flush() {
        if (title == "") return
        if (col in known && col != "✅ Done") printf "%s\x1f%d\x1f%s\x1f%s\x1e", col, tline, title, ctx
        else if (col == "✅ Done") { if (done++ == 0) { dtitle = title; dctx = ctx } }
        else { other++; if (!(col in seen)) { seen[col]; heads = heads (heads == "" ? "" : "\n") col } }
        title = ""; ctx = ""
      }
      /^## / { flush(); col = substr($0, 4); sub(/[ \t\r]+$/, "", col); hline = NR; next }
      NR == hline + 1 && col in known { blank[col] = ($0 ~ /^[ \t\r]*$/) }
      title != "" && NR == cend + 1 && /^\t/ { ctx = (ctx == "" ? $0 : ctx "\n" $0); cend = NR; next }
      /^- \[.\] / { flush(); title = $0; tline = NR; cend = NR }
      END {
        flush()
        for (i = 1; i <= ncols; i++) flags = flags (blank[cols[i]] ? 1 : 0)
        printf "\x1d\x1f%d\x1f%s\x1f%s\x1f%s\x1f%d\x1f%s\x1e", done, dtitle, dctx, flags, other, heads
      }' "$file")
    if [ -z "$match" ] && [ "${summary[4]}" -gt 0 ]; then
      printf 'board-scan: %s cards under other headings: %s\n' "${summary[4]}" "${summary[5]//$'\n'/, }" >&2
    fi
    jq -cn --argjson n "${summary[0]}" --arg dt "${summary[1]}" --arg dc "${summary[2]}" --arg flags "${summary[3]}" \
      --argjson other "${summary[4]}" --arg board "$board" --arg today "$today" '
      ["📥 Backlog", "📋 This Week", "🔨 In Progress", "⏳ Waiting On", "✅ Done"] as $cols
      | {done: $n, board: $board, today: $today,
        blank_after: ([range(5) | {key: $cols[.], value: ($flags[.:.+1] == "1")}] | from_entries),
        done_top: (if $dt == "" then null else {title_line: $dt, context_line: $dc} end),
        other: $other}'
    ;;
  prompt)
    task="${2:-}"
    if [ -z "$task" ] || [ ! -f "$vault/$task" ]; then
      printf 'board-scan: no task note %s in %s.\n' "$task" "$vault" >&2
      exit 2
    fi
    if ! prompt_block "$vault/$task"; then
      printf 'board-scan: %s has no prompt block under ## Prompt.\n' "$task" >&2
      exit 1
    fi
    ;;
  inbox)
    # A message longer than this is cut: the output goes into the orchestrator context.
    max=2000
    count=0
    # A dot file is a Syncthing temp file of a message that is not complete: the glob
    # skips it.
    for path in "$vault"/_inbox/*.md; do
      [ -f "$path" ] || continue
      count=$((count + 1))
      jq -cn --arg file "_inbox/${path##*/}" --rawfile text "$path" --argjson max "$max" '
        {file: $file, text: $text[:$max], truncated: (($text | length) > $max)}'
    done
    boards=()
    for path in "$vault"/Boards/*.md; do
      if [ ! -f "$path" ] || ! grep -q '^kanban-plugin: board' "$path"; then continue; fi
      name="${path##*/}"
      boards+=("${name%.md}" "$(grep -o '\[\[Projects/[^]|#]*' "$path" | cut -c3- | sort -u || true)")
    done
    jq -cn --argjson n "$count" '$ARGS.positional as $a
      | {inbox: $n, boards: ([range(0; $a | length; 2) | {key: $a[.],
        value: ($a[. + 1] | split("\n") | map(select(. != "")))}] | from_entries)}' --args ${boards[@]+"${boards[@]}"}
    ;;
  rules)
    [ -f "$vault/_CLAUDE.md" ] || exit 0
    awk '/^## / { keep = (index($0, "## Section 0 ") == 1 || $0 ~ /Frontmatter/ || $0 ~ /Do Not Touch/) }
      keep' "$vault/_CLAUDE.md"
    ;;
  *)
    printf 'usage: board-scan.sh cards BOARD | card BOARD TEXT | prompt TASK | inbox | rules\n' >&2
    exit 2
    ;;
esac
