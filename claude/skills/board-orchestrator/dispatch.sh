#!/usr/bin/env bash
# Tool of the board orchestrator on herdr-app: run a worker claude as an hc child of the
# orchestrator, and the board commands that need no Herdr (report, run-add, note-add,
# log, inbox-clear, policy, policy-set).
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

# The calls that push or write to a forge. policy-set adds each one of the forge.
GH_PUSH_RULES=('Bash(git push*)' 'Bash(git -C * push*)' 'Bash(git -c * push*)' 'Bash(gh pr create*)'
  'Bash(gh pr comment*)' 'Bash(gh pr edit*)' 'Bash(gh pr ready*)' 'Bash(gh pr close*)'
  'Bash(gh issue create*)' 'Bash(gh issue comment*)' 'Bash(gh issue edit*)')
FORGEJO_PUSH_RULES=('Bash(git push*)' 'Bash(git -C * push*)' 'Bash(git -c * push*)'
  mcp__forgejo__create_pull_request mcp__forgejo__update_pull_request
  mcp__forgejo__create_issue mcp__forgejo__update_issue mcp__forgejo__create_issue_comment
  mcp__forgejo__edit_issue_comment mcp__forgejo__issue_state_change)
# The calls that merge a PR. A worker never merges: policy-set adds each one of the
# forge to deny.
GH_MERGE_RULES=('Bash(gh pr merge*)' 'Bash(tea pr merge*)' 'Bash(tea pulls merge*)'
  'mcp__forgejo__merge_pull_request')
FORGEJO_MERGE_RULES=('Bash(tea pr merge*)' 'Bash(tea pulls merge*)' 'mcp__forgejo__merge_pull_request')
# The rules of the old policy-set that do more than push and comment. policy-set
# removes each one from allow and ask.
OLD_RULES=('Bash(gh pr merge*)' 'Bash(gh pr review*)' 'Bash(gh release*)' 'Bash(gh repo create*)'
  'Bash(gh gist*)' 'Bash(gh api -X*)' 'Bash(gh api --method*)')
# The gh rules that policy-set wrote. For Forgejo, policy-set removes each one from
# allow, ask and deny.
GH_RULES=('Bash(gh pr create*)' 'Bash(gh pr comment*)' 'Bash(gh pr edit*)' 'Bash(gh pr ready*)'
  'Bash(gh pr close*)' 'Bash(gh issue create*)' 'Bash(gh issue comment*)' 'Bash(gh issue edit*)'
  "${OLD_RULES[@]}")

set_claude_args() {
  local mode=$1 cwd=$2 report=$3
  local off='{"enabledPlugins":{"obsidian-second-brain@obsidian-second-brain":false}}'
  claude_args=()
  # The worker reports with hc send to the orchestrator that runs this script.
  local send="Bash(hc send ${HC_TERMINAL_ID:-} *)"
  if [ "$mode" != auto ]; then
    claude_args+=(--settings "$off" --allowedTools "$send")
    return 0
  fi
  # One --settings value: the readonly settings with the plugin switch merged in.
  claude_args+=(--setting-sources user --settings "$(jq -c --argjson off "$off" '. * $off' "$cwd/.claude/settings.readonly.json")" --permission-mode dontAsk)
  [ ! -f "$cwd/.mcp.json" ] || claude_args+=(--mcp-config "$cwd/.mcp.json")
  # --allowedTools takes many values, so it must be the last option. A claude rule for an
  # absolute path starts with a double slash. Edit also covers Write.
  claude_args+=(--allowedTools "Edit(/$report)" "$send")
}

# Print the allow rules of CWD/.claude/settings.readonly.json, one for each line, with no
# empty rule. When the file is missing, is not valid JSON or has no rule, write the reason
# to stderr and return 2.
readonly_rules() {
  local file="$1/.claude/settings.readonly.json" list rules
  if [ ! -f "$file" ] || ! list=$(jq -r '.permissions.allow // [] | .[] | strings' "$file" 2>/dev/null); then
    printf 'dispatch: %s is missing or is not valid JSON.\n' "$file" >&2
    return 2
  fi
  rules=$(grep -v '^$' <<<"$list" || true)
  if [ -z "$rules" ]; then
    printf 'dispatch: %s has no rule in permissions.allow.\n' "$file" >&2
    return 2
  fi
  printf '%s\n' "$rules"
}

# common_dir DIR: the real path of the git common dir of DIR (the .git folder of the main
# checkout). Exit 1 outside git.
common_dir() {
  local d
  d=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  (cd -- "$1" && cd -- "$d" && pwd -P)
}

# main_dir DIR: the same folder in the main checkout when DIR is in a linked git worktree,
# else DIR. A new worktree has no direnv allow: its worker uses the main checkout env.
main_dir() {
  local top common
  if top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && common=$(common_dir "$1") &&
    [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")${1#"$top"}" ]; then
    printf '%s%s\n' "$(dirname "$common")" "${1#"$top"}"
  else
    printf '%s\n' "$1"
  fi
}

# card_worktree DIR SLUG: the folder of the work of the card SLUG, the same folder as DIR
# in a git worktree on the branch SLUG, beside the main checkout: REPO-SLUG (else
# REPO-SLUG-2, ...). The worker claude starts there, so herdr-app and herdr-reviewr see
# where it works. It uses the worktree again when it is there. A new branch starts at
# origin/HEAD (else HEAD), with no upstream: a push never goes to the default branch. DIR
# when DIR is not in a main git checkout. Exit 1 when git fails.
card_worktree() {
  local dir=$1 slug=$2 top common path base err="" n=2 rel
  if ! top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || ! common=$(common_dir "$dir") ||
    [ "$common" != "$(cd -- "$top" && pwd -P)/.git" ]; then
    printf '%s\n' "$dir"
    return 0
  fi
  rel=${dir#"$top"}
  path="$(dirname "$top")/$(basename "$top")-$slug"
  while [ -e "$path" ]; do
    if [ "$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" = "$path" ] &&
      [ "$(common_dir "$path")" = "$common" ] &&
      [ "$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$slug" ]; then
      break
    fi
    path="$(dirname "$top")/$(basename "$top")-$slug-$n"
    n=$((n + 1))
  done
  if [ ! -e "$path" ]; then
    # No prompt for a password: dispatch runs with no person at the terminal.
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
      git -C "$top" fetch -q origin >/dev/null 2>&1 || true
    if git -C "$top" show-ref -q --verify "refs/heads/$slug"; then
      err=$(git -C "$top" worktree add -q "$path" "$slug" 2>&1) && err=""
    elif base=$(git -C "$top" rev-parse -q --verify 'origin/HEAD^{commit}' 2>/dev/null) ||
      base=$(git -C "$top" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null); then
      err=$(git -C "$top" worktree add -q -b "$slug" "$path" "$base" 2>&1) && err=""
    else
      err="no origin/HEAD and no HEAD"
    fi
    if [ -n "$err" ] || [ ! -d "$path" ]; then
      printf 'dispatch: could not make a worktree for %s in %s: %s\n' "$slug" "$top" "${err:-git made no folder}" >&2
      return 1
    fi
  fi
  # The push policy (policy-set) is in an ignored file: the worktree uses the one of DIR.
  if [ -f "$dir/.claude/settings.local.json" ] && [ ! -e "$path$rel/.claude/settings.local.json" ]; then
    mkdir -p "$path$rel/.claude"
    ln -s "$dir/.claude/settings.local.json" "$path$rel/.claude/settings.local.json"
  fi
  printf '%s%s\n' "$path" "$rel"
}

# The workers: one line "ADDRESS<tab>MODE<tab>BOARD<tab>REPORT<tab>SESSION<tab>CWD<tab>NAME"
# for each worker that start or resume opened. A line stays after the worker ends: a new
# orchestrator offers to resume it (resumable).
workers_file() { printf '%s/workers\n' "$(state_dir)"; }

# The slugs of the cards: one line "SLUG<tab>KEY" for each card that start task got. KEY
# is the full title in the form of a slug, with no cut: another case or other marks in
# the title give the same card. board_slug cuts a long title, so 2 cards can give the
# same slug.
cards_file() { printf '%s/cards\n' "$(state_dir)"; }

# card_slug NAME: the slug of the task card NAME, for its branch, worktree, agent and
# report: the slug that the cards file gives NAME. Else the board slug of NAME, or that
# slug with -2, -3 when another card has it. The cards file then keeps it. A lock folder
# (a Mac has no flock) keeps 2 starts at the same time from taking the same slug.
card_slug() {
  local key base f lock tries=50
  key=$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs 'a-z0-9' '-')
  key=$(sed 's/^-*//; s/-*$//' <<<"$key")
  base=$(board_slug "$1")
  base=${base:-worker}
  key=${key:-$base}
  f=$(cards_file)
  lock="$f.lock"
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries - 1))
    if [ "$tries" -le 0 ]; then
      printf 'dispatch: another start holds %s\n' "$lock" >&2
      return 1
    fi
    sleep 0.1
  done
  # card_slug runs in a $( ) subshell: this trap frees the lock when it ends early.
  # shellcheck disable=SC2064
  trap "rmdir $(printf '%q' "$lock") 2>/dev/null || true" EXIT
  touch "$f"
  # One awk reads the whole file: a grep -q in a pipe stops early, and with pipefail the
  # SIGPIPE of the writer reads as no match. "" makes awk compare strings, not numbers.
  awk -F '\t' -v OFS='\t' -v k="$key" -v b="$base" -v f="$f" '
    $2 "" == k "" { print $1; found = 1; exit }
    { taken[$1 ""] = 1 }
    END {
      if (found) exit
      s = b; n = 2
      while (s in taken) s = b "-" n++
      print s
      print s, k >>f
    }' "$f"
  rmdir "$lock" 2>/dev/null || true
}

# unique_name SLUG: SLUG, or SLUG-2, SLUG-3 when a live hc terminal has that name.
unique_name() {
  local names n=2 name=$1
  names=$("${HC[@]}" ls --json 2>/dev/null | jq -r '.terminals[]?.name // empty' 2>/dev/null) || names=""
  while grep -qxF -- "$name" <<<"$names"; do
    name="$1-$n"
    n=$((n + 1))
  done
  printf '%s\n' "$name"
}

# caller_board: the board of the orchestrator that runs this script, from its hc labels.
caller_board() {
  local labels
  if [ -z "${HC_TERMINAL_ID:-}" ]; then
    printf 'dispatch: HC_TERMINAL_ID is empty. Run this in the board orchestrator, in herdr-app.\n' >&2
    return 2
  fi
  if ! labels=$(hc_labels "$HC_TERMINAL_ID") ||
    [ "$(jq -r '.["board.role"] // empty' <<<"$labels")" != orchestrator ]; then
    printf 'dispatch: %s is not a board orchestrator.\n' "$HC_TERMINAL_ID" >&2
    return 2
  fi
  jq -r '.board' <<<"$labels"
}

# other_repos BOARD CWD SLUG: the text that lists the git repos of the projects of BOARD,
# except the repo of CWD: one "REPO (push policy P, worktree WT)" item for each, joined
# with "; ", then a tab and the "git worktree add" commands. Print nothing when there is
# no other repo.
other_repos() {
  local board=$1 cwd=$2 slug=$3 vault file own note repo top common base wt items="" cmds=""
  local -A seen=()
  vault=$(vault_path) || return 0
  file="$vault/Boards/$board.md"
  [ -f "$file" ] || return 0
  own=$(common_dir "$cwd" 2>/dev/null) || own=""
  while IFS= read -r note; do
    repo=$(project_repo "$vault/$note.md")
    [ -n "$repo" ] || continue
    top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || continue
    common=$(common_dir "$top") || continue
    if [ "$common" = "$own" ] || [ -n "${seen[$common]:-}" ]; then continue; fi
    seen[$common]=1
    base=HEAD
    git -C "$top" rev-parse -q --verify 'origin/HEAD^{commit}' >/dev/null 2>&1 && base=origin/HEAD
    wt="$top-$slug"
    items="${items:+$items; }$top (push policy $( (push_policy "$top") 2>/dev/null || echo invalid), worktree $wt)"
    cmds="${cmds:+$cmds, or }git -C $top worktree add -b $slug $wt $base"
  done < <(grep -o '\[\[Projects/[^]|#]*' "$file" | cut -c3- | sort -u || true)
  [ -z "$items" ] || printf '%s\t%s\n' "$items" "$cmds"
}

# footer MODE CWD REPORT SLUG RULES...: the text after the task, for the worker. A task
# worker also gets the other repos of $board (set by start).
footer() {
  local mode=$1 cwd=$2 report=$3 slug=$4 vault text others=""
  shift 4
  text="When you finish, write your report to $report. Do not merge, deploy or change production. Write the report in one Write call, as your last step. Do not edit the vault. When the user asks for a change to the board or to a task note, write it in the report under a heading ## Vault changes, one change for each item. For a new task, write only its title, its project, its priority and one context line: the orchestrator writes the card in the board format, so do not read the vault for it. For a change to existing text, give the note path and the exact old and new text only in the report. Do not show them in the conversation: write there only that the report has vault changes. When the user answers you or asks for more work after your report, write the full report again when you finish. The new report replaces the old one. After the first line, write a section ## Result of at most 10 lines: the result, and the PR, commit or issue links. Do not change the herdr-app window."
  text="$text After you write the report, run: hc send $HC_TERMINAL_ID \"report $slug $report\""
  # An auto check can use only its listed tools, so only a task worker gets this.
  [ "$mode" != task ] ||
    text="$text You can start subagents and other claude terminals, for example for an independent review of your work before you push."
  # Workers of one board can need the same long job (a wait for a deploy). A name from the
  # job lets them find it, and hc refuses a second live terminal with that name. An hc child
  # ends with its parent: --outlive-parent keeps the job when the orchestrator closes the
  # worker that started it.
  if [ "$mode" = task ]; then
    text="$text Run a long job (a wait for a deploy, a build) in a named hc terminal, so that other workers can use the same job. Name the job after what it does, not after your card, for example deploy-web-4fb7f80. First run: hc get <job>. When it shows the job, use it and do not start it again. Else start it: hc run --bg --no-notify --outlive-parent --name <job> --cwd <dir> -- <command>. On name_taken, another worker started it first: use that job. To use a job, run hc wait <job> --timeout 3600 as a background Bash call, end your turn with \"I wait for <job>.\", then read exit_code in its JSON and the end of the job with hc read <job> | tail -40. On reason timeout or message, wait again. Do not hc rm or hc kill a shared job: another worker can still use it."
  fi
  # A worker has no obsidian plugin (set_claude_args), so it gets the way to read the vault.
  if vault=$(vault_path); then
    text="$text The vault is at $vault. To read it, read _CLAUDE.md first, then grep the vault and read the notes."
  fi
  # The allow rules of a repo apply to the whole session, in all folders: a worker could
  # push to another repo with them. So the prompt keeps the worker in its own repo, and in
  # the other repos of its board with the push policy of each.
  [ "$mode" != task ] || others=$(other_repos "$board" "$cwd" "$slug")
  if [ -z "$others" ]; then
    text="$text Change only the repo of your card: $cwd and its git worktrees. When the work needs another repo, do not change that repo: stop that work. Write it in the report as a new task under ## Vault changes, with the repo, the work and the reason on its context line. The orchestrator starts a worker in that repo."
  else
    text="$text Change only the repo of your card: $cwd and its git worktrees, and the other repos of your board below. When the work needs a repo that is not in that list, do not change that repo: stop that work. Write it in the report as a new task under ## Vault changes, with the repo, the work and the reason on its context line. The orchestrator starts a worker in that repo."
    text="$text The other repos of your board: ${others%%$'\t'*}. When the work of the card needs one of them, change it too, in a git worktree on your branch: run ${others#*$'\t'}, or use that worktree when it exists. Never change the main checkout of that repo. Follow the push policy of that repo, not the policy of your card: allow, push and open a PR; ask, ask the user before each push and each PR; deny, missing or invalid, do not push and give the branch in the report. Give the PR or commit links of each repo in the report."
  fi
  if [ "$mode" = task ]; then
    text="$text Start the report with one line: RESULT: DONE when the work of the card is complete, or RESULT: WAITS FOR USER when the user must act (a PR to review or merge, a question, a decision)."
    # The orchestrator keeps a done task worker open: the user closes it by a word to it.
    text="$text When the user tells you to close, run: hc send $HC_TERMINAL_ID \"close $slug\" and end your turn. The orchestrator then closes you."
  fi
  if [ "$mode" = auto ]; then
    text="$text Start the report with one line: STATUS: OK, STATUS: STOP or STATUS: REFUSED. Write STATUS: REFUSED when claude refused a call that the check needs, and add one line REFUSED: <command> for each refused call. Give each value with OK or STOP. Do not trip a kill switch."
    text="$text"$'\n\n'"You can use only these tools. Claude refuses all other calls."
    text="$text"$'\n'"$(printf '%s\n' "$@")"
    text="$text"$'\n'"You can also write the report file with the Edit or Write tool."
    text="$text"$'\n'"Run each command exactly in the form of its rule, from the start folder. Do not add another cd or -C, and do not add ; or &&. If a call is refused, do not try another form: write the refused command in the report."
  fi
  printf '%s\n' "$text"
}

# run_worker MODE BOARD CWD NAME SESSION REPORT PROMPT [CLAUDE_FLAGS...]: start the worker
# claude as an hc child of the caller. Prints the address.
run_worker() {
  local mode=$1 board=$2 cwd=$3 name=$4 session=$5 report=$6 prompt=$7 out envdir
  local -a env_cmd=()
  shift 7
  set_claude_args "$mode" "$cwd" "$report"
  # A project with an .envrc (a nix devshell) needs its tools on PATH (bao for the MCP
  # tokens): start the worker claude in that environment.
  envdir=$(main_dir "$cwd")
  if [ -f "$envdir/.envrc" ] && command -v direnv >/dev/null 2>&1; then
    env_cmd=(direnv exec "$envdir")
  fi
  # --allowedTools takes many values: -- ends the options before the prompt.
  out=$("${HC[@]}" run --json --bg --name "$(unique_name "$name")" --cwd "$cwd" \
    --label "board=$board" --label board.role=worker --label "board.session=$session" \
    -- ${env_cmd[@]+"${env_cmd[@]}"} claude "$@" -n "$name" ${claude_args[@]+"${claude_args[@]}"} -- "$prompt") || return 1
  jq -r '.address // empty' <<<"$out"
}

# worker_line ADDR: the record line of the worker ADDR, if any.
worker_line() {
  local f
  f=$(workers_file)
  [ ! -f "$f" ] || awk -F '\t' -v a="$1" '$1 == a { line = $0 } END { if (line != "") print line }' "$f"
}

# live_session LINE: exit 0 when the worker of the record LINE runs: its address is a
# live worker of its board with the same session.
live_session() {
  local addr board session labels
  addr=$(cut -f1 <<<"$1") board=$(cut -f3 <<<"$1") session=$(cut -f5 <<<"$1")
  labels=$(hc_labels "$addr") || return 1
  jq -e --arg b "$board" --arg s "$session" \
    '.board == $b and .["board.role"] == "worker" and .["board.session"] == $s' <<<"$labels" >/dev/null 2>&1
}

# agent_state ADDR: the agent status of ADDR (working, blocked, idle, done), or empty.
agent_state() {
  "${HC[@]}" get "$1" --json 2>/dev/null | jq -r '.status.state // empty' 2>/dev/null || true
}

# rewrite_workers AWK_PROGRAM [VAR=VALUE...]: rewrite the record through awk.
rewrite_workers() {
  local f tmp prog=$1
  shift
  f=$(workers_file)
  [ -f "$f" ] || return 0
  tmp=$(mktemp "$f.XXXXXX")
  awk -F '\t' -v OFS='\t' "$@" "$prog" "$f" >"$tmp"
  mv "$tmp" "$f"
}

# file_mtime FILE: the modification time in seconds. GNU stat takes -c, macOS stat -f.
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# need_worker ADDR: exit 1 with "no agent" when ADDR is not a live worker.
need_worker() {
  local labels
  if ! labels=$(hc_labels "$1") || [ "$(jq -r '.["board.role"] // empty' <<<"$labels")" != worker ]; then
    printf 'dispatch: no agent in %s.\n' "$1" >&2
    exit 1
  fi
}

case "${1:-}" in
  policy)
    push_policy "${2:-}"
    ;;
  policy-set)
    cwd="${2:-}" kind="${3:-}"
    if [ "$kind" != allow ] && [ "$kind" != ask ]; then
      printf 'usage: dispatch.sh policy-set CWD allow|ask\n' >&2
      exit 2
    fi
    if [ ! -d "$cwd" ]; then
      printf 'dispatch: %s is not a folder.\n' "$cwd" >&2
      exit 2
    fi
    # Forgejo is the default: only github.com uses gh.
    url=$(git -C "$cwd" remote get-url origin 2>/dev/null) || url=
    host=${url#*://}
    host=${host#*@}
    host=${host%%[:/]*}
    if [ "$host" = github.com ]; then
      push_rules=("${GH_PUSH_RULES[@]}")
      merge_rules=("${GH_MERGE_RULES[@]}")
      gh_rules=()
    else
      push_rules=("${FORGEJO_PUSH_RULES[@]}")
      merge_rules=("${FORGEJO_MERGE_RULES[@]}")
      gh_rules=("${GH_RULES[@]}")
    fi
    file="$cwd/.claude/settings.local.json"
    current=$(read_settings "$file") || exit 2
    mkdir -p "$cwd/.claude"
    tmp=$(mktemp "$file.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    if ! jq --arg k "$kind" --argjson push "$(jq -n '$ARGS.positional' --args "${push_rules[@]}")" \
      --argjson merge "$(jq -n '$ARGS.positional' --args "${merge_rules[@]}")" \
      --argjson drop "$(jq -n '$ARGS.positional' --args "${OLD_RULES[@]}")" \
      --argjson gh "$(jq -n '$ARGS.positional' --args "${gh_rules[@]}")" '
      def add($k; $r): .permissions[$k] = ((.permissions[$k] // []) as $old | $old + [$r[] | select(. as $x | $old | index([$x]) | not)]);
      reduce ("allow", "ask") as $l (.;
        if .permissions[$l] == null then . else .permissions[$l] |= map(select(. as $x | $drop | index([$x]) | not)) end)
      | reduce ("allow", "ask", "deny") as $l (.;
        if .permissions[$l] == null then . else .permissions[$l] |= map(select(. as $x | $gh | index([$x]) | not)) end)
      # ask wins over allow: remove the push rules from the other list first.
      | (if $k == "allow" then "ask" else "allow" end) as $o
      | (if .permissions[$o] == null then . else .permissions[$o] |= map(select(. as $x | $push | index([$x]) | not)) end)
      | add($k; $push) | add("deny"; $merge)' <<<"$current" >"$tmp" || [ ! -s "$tmp" ]; then
      printf 'dispatch: could not write %s.\n' "$file" >&2
      exit 2
    fi
    # The macOS chmod has no --reference.
    if [ -e "$file" ]; then
      chmod "$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file")" "$tmp"
    else
      chmod 644 "$tmp"
    fi
    mv "$tmp" "$file"
    trap - EXIT
    push_policy "$cwd"
    ;;
  report)
    file="${2:-}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
      printf 'usage: dispatch.sh report PATH\n' >&2
      exit 2
    fi
    # The orchestrator reads this, not the full report: a full report fills its context.
    awk -v path="$file" -v max=60 '
      function keep(name, text) {
        n[name]++
        if (n[name] <= max) buf[name] = buf[name] text "\n"
      }
      function out(name) {
        printf "%s", buf[name]
        if (n[name] > max) printf "[section cut: %d more lines]\n", n[name] - max
      }
      NR == 1 { first = $0 }
      NR <= 40 { head = head $0 "\n" }
      /^## / {
        sec = ""
        if ($0 ~ /^## Result[ \t\r]*$/) { sec = "result"; seen = 1 }
        else if ($0 ~ /^## Vault changes[ \t\r]*$/) sec = "vault"
      }
      sec != "" { keep(sec, $0); next }
      NR > 1 && /^REFUSED:/ { refused = refused $0 "\n" }
      END {
        if (seen) { print first; out("result"); out("vault"); printf "%s", refused }
        else printf "%s", head
        printf "full report: %s (%d lines)\n", path, NR
      }' "$file"
    ;;
  run-add)
    rel="${2:-}" file="${3:-}"
    if [ -z "$rel" ] || [ -z "$file" ] || [ ! -f "$file" ]; then
      printf 'usage: dispatch.sh run-add NOTE REPORT\n' >&2
      exit 2
    fi
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    note="$vault/$rel"
    if [ ! -f "$note" ]; then
      printf 'dispatch: no task note %s in the vault.\n' "$rel" >&2
      exit 1
    fi
    day=$(date +%F)
    # The script copies the full report, so that the report text does not go through the
    # orchestrator context. The report files are on one host only, the vault is on all.
    tmp=$(mktemp "$(dirname "$note")/.run-add.XXXXXX")
    awk -v day="$day" '
      # The report: demote its headings by 3 levels to put them under the day line.
      # A "#" line in a code block is not a heading.
      FILENAME == ARGV[1] {
        if ($0 ~ /^[ \t]*(```|~~~)/) fence = !fence
        if (!fence && $0 ~ /^#+ /) $0 = "###" $0
        rep[++nr] = $0
        next
      }
      { line[++n] = $0 }
      END {
        while (nr > 0 && rep[nr] ~ /^[ \t\r]*$/) nr--
        i = 1
        if (line[1] == "---") {
          for (i = 2; i <= n && line[i] != "---"; i++)
            if (line[i] ~ /^updated:/) line[i] = "updated: " day
          i++
        }
        # Find ## Runs, its end, and the entry of today in it. A record of the same card
        # again on the same day (after a watch exit 0) replaces that entry. A "#" line in a
        # code block of an old run is not a heading.
        for (; i <= n; i++) {
          if (line[i] ~ /^[ \t]*(```|~~~)/) { nfence = !nfence; continue }
          if (nfence) continue
          if (runs && line[i] ~ /^## /) { end = i; break }
          if (line[i] ~ /^## Runs[ \t\r]*$/) runs = i
          if (runs && line[i] ~ /^### /) {
            if (from && !to) to = i
            if (line[i] ~ ("^### " day "[ \t\r]*$")) { from = i; to = 0 }
          }
        }
        if (!end) end = n + 1
        if (from && !to) to = end
        # The new run replaces the lines cut to rest - 1.
        if (from) { cut = from; rest = to }
        else { cut = end; rest = end }
        last = cut - 1
        while (last > 0 && line[last] ~ /^[ \t\r]*$/) last--
        for (k = 1; k <= last; k++) print line[k]
        if (last) print ""
        if (!runs) { print "## Runs"; print "" }
        print "### " day
        print ""
        for (k = 1; k <= nr; k++) print rep[k]
        while (rest <= n && line[rest] ~ /^[ \t\r]*$/) rest++
        if (rest <= n) print ""
        for (k = rest; k <= n; k++) print line[k]
      }' "$file" "$note" >"$tmp"
    mv "$tmp" "$note"
    printf 'run-add: %s %s\n' "$rel" "$day"
    ;;
  note-add)
    rel="${2:-}" board="${3:-}" at="${4:-}" title="${5:-}"
    if [ -z "$rel" ] || [ -z "$board" ] || [[ ! "$at" =~ ^[1-9][0-9]*$ ]] || [ -z "$title" ]; then
      printf 'usage: dispatch.sh note-add NOTE BOARD LINE TITLE\n' >&2
      exit 2
    fi
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    note="$vault/$rel" file="$vault/Boards/$board.md"
    if [ ! -f "$note" ]; then
      printf 'dispatch: no task note %s in the vault.\n' "$rel" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      printf 'dispatch: no board %s in the vault.\n' "$board" >&2
      exit 1
    fi
    # The script copies the card text, so that the long text does not go through the
    # orchestrator context. The line number comes from a scan just before: the user can
    # edit the board in between, so the card TITLE must still be at that line.
    text=$(awk -v at="$at" '
      NR < at { next }
      NR == at { if ($0 !~ /^- \[.\] /) exit 3; card = $0; next }
      /^\t/ { sub(/^\t/, ""); ctx = ctx (ctx == "" ? "" : "\n") $0; card = card "\n" $0; next }
      { exit }
      END { if (card == "") exit 3; print card; if (ctx == "") exit 4; print "\x1e"; print ctx }' "$file") && rc=0 || rc=$?
    # The title is the text between the first ** and the next **, as in board-scan.sh.
    first=${text%%$'\n'*} found=""
    if [ "$rc" -ne 3 ] && [[ "$first" == *'**'*'**'* ]]; then
      found=${first#*\*\*} found=${found%%\*\**}
    fi
    if [ "$rc" -eq 3 ] || [ "$found" != "$title" ]; then
      printf 'dispatch: no card %s at line %s of Boards/%s.md.\n' "$title" "$at" "$board" >&2
      exit 1
    fi
    case $rc in
      0) ;;
      *)
        printf 'dispatch: the card at line %s of Boards/%s.md has no context line.\n' "$at" "$board" >&2
        exit 1
        ;;
    esac
    card=${text%%$'\n\x1e\n'*} ctx=${text#*$'\n\x1e\n'}
    # A card can also link related task notes. A card with no task link is new: the
    # orchestrator made its note just before.
    links=$(grep -o '\[\[Tasks/[^]|#]*' <<<"$card" | cut -c3- || true)
    if [ -n "$links" ] && ! grep -qxF "${rel%.md}" <<<"$links"; then
      printf 'dispatch: the card at line %s of Boards/%s.md links %s, not %s.\n' "$at" "$board" "${links%%$'\n'*}" "$rel" >&2
      exit 1
    fi
    day=$(date +%F)
    tmp=$(mktemp "$(dirname "$note")/.note-add.XXXXXX")
    # awk -v would read the backslashes of the text as escapes: ENVIRON keeps them.
    NOTE_TEXT="$ctx" awk -v day="$day" '
      BEGIN {
        na = split(ENVIRON["NOTE_TEXT"], add, "\n")
        # Put each heading of the text under the ### entry. A "#" line in a code block is
        # not a heading.
        for (k = 1; k <= na; k++) {
          if (add[k] ~ /^[ \t]*(```|~~~)/) tfence = !tfence
          else if (!tfence && add[k] ~ /^#+ /) add[k] = "###" add[k]
        }
      }
      { line[++n] = $0 }
      END {
        i = 1
        if (line[1] == "---") {
          for (i = 2; i <= n && line[i] != "---"; i++)
            if (line[i] ~ /^updated:/) line[i] = "updated: " day
          i++
        }
        # Find ## Notes and its end. A "#" line in a code block is not a heading.
        for (; i <= n; i++) {
          if (line[i] ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
          if (fence) continue
          if (notes && line[i] ~ /^## /) { end = i; break }
          if (line[i] ~ /^## Notes[ \t\r]*$/) notes = i
        }
        if (!end) end = n + 1
        last = end - 1
        while (last > 0 && line[last] ~ /^[ \t\r]*$/) last--
        for (k = 1; k <= last; k++) print line[k]
        if (last) print ""
        if (!notes) { print "## Notes"; print "" }
        print "### " day ", from the board"
        print ""
        for (k = 1; k <= na; k++) print add[k]
        rest = end
        while (rest <= n && line[rest] ~ /^[ \t\r]*$/) rest++
        if (rest <= n) print ""
        for (k = rest; k <= n; k++) print line[k]
      }' "$note" >"$tmp"
    mv "$tmp" "$note"
    printf 'note-add: %s %s\n' "$rel" "$day"
    ;;
  log)
    board="${2:-}" file="${3:-}"
    if [ -z "$board" ] || [ -z "$file" ]; then
      printf 'usage: dispatch.sh log BOARD FILE\n' >&2
      exit 2
    fi
    if [ ! -s "$file" ]; then
      printf 'dispatch: the log file %s is missing or empty.\n' "$file" >&2
      exit 2
    fi
    # The log has one line for each card: a line end in the text becomes a space.
    text=$(tr '\n' ' ' <"$file")
    text="${text% }"
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    day=$(date +%F)
    name="$day - $board (board orchestrator)"
    note="$vault/Dev Logs/$name.md"
    if [ ! -f "$note" ]; then
      mkdir -p "$vault/Dev Logs"
      cat >"$note" <<NOTE
---
date: $day
type: devlog
board: "[[Boards/$board]]"
tags: [devlog, board-orchestrator, $board]
ai-first: true
---

## For future agent
This note is the work log of the board orchestrator of [[Boards/$board]] for $day. Each line under Log is the result of one card: the time, the card title, the result, the links and the report path. The orchestrator writes a line when it records a card on the board. For the details of a card, read its report.

## Log
NOTE
    fi
    # Log is the last section of the note: a new line goes at the end.
    printf -- '- %s %s\n' "$(date +%H:%M)" "$text" >>"$note"
    daily="$vault/Daily/$day.md"
    if [ -f "$daily" ] && ! grep -qF "[[Dev Logs/$name" "$daily"; then
      # The temp file is in the same folder, so that mv replaces the note in one step.
      tmp=$(mktemp "$vault/Daily/.$day.XXXXXX")
      # Put the link after the last line that is not blank in the Work section, else
      # at the end of the note.
      awk -v link="- [[Dev Logs/$name]]" '
        { line[NR] = $0 }
        /^## / { work = ($0 ~ /^## Work[ \t\r]*$/); if (work) at = NR }
        work && $0 !~ /^[ \t\r]*$/ { at = NR }
        END {
          if (!at) at = NR
          for (i = 1; i <= NR; i++) { print line[i]; if (i == at) print link }
        }' "$daily" >"$tmp"
      mv "$tmp" "$daily"
    fi
    ;;
  inbox-clear)
    rel="${2:-}"
    # One path part after _inbox/, no dot file: the command cannot reach a note out of
    # the inbox or a Syncthing temp file.
    if ! [[ "$rel" =~ ^_inbox/[^/.][^/]*\.md$ ]]; then
      printf 'usage: dispatch.sh inbox-clear _inbox/NAME.md\n' >&2
      exit 2
    fi
    if ! vault=$(vault_path); then
      printf 'dispatch: no vault path: set OBSIDIAN_VAULT_PATH.\n' >&2
      exit 1
    fi
    if [ ! -f "$vault/$rel" ]; then
      printf 'dispatch: %s is gone from the vault.\n' "$rel" >&2
      exit 1
    fi
    rm -- "$vault/$rel"
    printf 'inbox-clear: %s\n' "$rel"
    ;;
  start)
    mode="${2:-}" cwd="${3:-}" name="${4:-}" prompt_file="${5:-}"
    if [ "$mode" != task ] && [ "$mode" != auto ] || [ -z "$cwd" ] || [ -z "$name" ] || [ ! -f "$prompt_file" ]; then
      printf 'usage: dispatch.sh start task|auto CWD NAME PROMPT_FILE\n' >&2
      exit 2
    fi
    board=$(caller_board) || exit 2
    if [ ! -d "$cwd" ]; then
      printf 'dispatch: %s is not a folder.\n' "$cwd" >&2
      exit 2
    fi
    cwd=$(cd -- "$cwd" >/dev/null && pwd -P)
    rules=()
    if [ "$mode" = task ] && [ "$(push_policy "$cwd")" = missing ]; then
      printf 'dispatch: no push policy for %s: run dispatch.sh policy-set\n' "$cwd" >&2
      exit 2
    fi
    if [ "$mode" = auto ]; then
      list=$(readonly_rules "$cwd") || exit 2
      while IFS= read -r rule; do
        rules+=("$rule")
      done <<<"$list"
      rules+=("Bash(hc send $HC_TERMINAL_ID *)")
    fi
    # A task worker works in its own worktree, on the branch of its card. An auto check
    # reads only: the repo.
    work=$cwd
    if [ "$mode" = task ]; then
      slug=$(card_slug "$name") || exit 1
      work=$(card_worktree "$cwd" "$slug") || exit 1
    else
      slug=$(board_slug "$name")
      slug=${slug:-worker}
    fi
    report="$(state_dir)/$slug-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM.md"
    session=$(new_uuid)
    prompt="$(<"$prompt_file")"$'\n\n'"$(footer "$mode" "$cwd" "$report" "$slug" ${rules[@]+"${rules[@]}"})"
    if [ "$work" != "$cwd" ]; then
      prompt="$prompt Your git worktree is $work, on the branch $(git -C "$work" rev-parse --abbrev-ref HEAD). Do the work there. Rename the branch with git branch -m when the repo wants another name."
    fi
    if ! addr=$(run_worker "$mode" "$board" "$work" "$slug" "$session" "$report" "$prompt" --session-id "$session") || [ -z "$addr" ]; then
      printf 'dispatch: hc did not start the worker.\n' >&2
      exit 1
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$addr" "$mode" "$board" "$report" "$session" "$work" "$slug" >>"$(workers_file)"
    printf '%s\n%s\n' "$addr" "$report"
    ;;
  workers)
    board="${2:?usage: dispatch.sh workers BOARD}"
    f=$(workers_file)
    [ -f "$f" ] || exit 0
    while IFS= read -r line; do
      if [ "$(cut -f3 <<<"$line")" != "$board" ] || ! live_session "$line"; then continue; fi
      IFS=$'\t' read -r addr mode _ report session cwd name <<<"$line"
      status=$(agent_state "$addr")
      exists=false first="" mtime=""
      if [ -n "$report" ] && [ -f "$report" ]; then
        exists=true
        first=$(head -n 1 "$report")
        printf -v mtime '%(%Y-%m-%dT%H:%M:%S%z)T' "$(file_mtime "$report")"
        mtime="${mtime:0:22}:${mtime:22}"
      fi
      waits=false
      case "$status" in
        blocked) waits=true ;;
        idle | done) case "$first" in "RESULT: DONE"* | "STATUS: OK"*) ;; *) waits=true ;; esac ;;
      esac
      jq -cn --arg address "$addr" --arg name "$name" --arg status "$status" --arg mode "$mode" \
        --arg cwd "$cwd" --arg session "$session" --arg report "$report" --argjson exists "$exists" \
        --arg first "$first" --arg mtime "$mtime" --argjson waits "$waits" '
        def n: if . == "" then null else . end;
        {address: $address, name: ($name | n), status: ($status | n), mode: ($mode | n),
          cwd: ($cwd | n), session: ($session | n), report: ($report | n), report_exists: $exists,
          first_line: ($first | n), report_mtime: ($mtime | n), waits: $waits}'
    done <"$f"
    ;;
  resumable)
    board="${2:?usage: dispatch.sh resumable BOARD}"
    f=$(workers_file)
    [ -f "$f" ] || exit 0
    while IFS= read -r line; do
      [ "$(cut -f3 <<<"$line")" = "$board" ] || continue
      ! live_session "$line" || continue
      IFS=$'\t' read -r _ mode _ report session cwd name <<<"$line"
      first="" exists=false
      if [ -f "$report" ]; then
        exists=true
        first=$(head -n 1 "$report")
      fi
      jq -cn --arg session "$session" --arg mode "$mode" --arg cwd "$cwd" --arg name "$name" \
        --arg report "$report" --argjson exists "$exists" --arg first "$first" \
        '{session: $session, mode: $mode, cwd: $cwd, name: $name, report: $report,
          report_exists: $exists, first_line: $first,
          done: ($first | startswith("RESULT: DONE") or startswith("STATUS: OK"))}'
    done <"$f"
    ;;
  resume)
    board="${2:-}" session="${3:-}"
    if [ -z "$board" ] || [ -z "$session" ]; then
      printf 'usage: dispatch.sh resume BOARD SESSION\n' >&2
      exit 2
    fi
    caller_board >/dev/null || exit 2
    f=$(workers_file)
    line=""
    [ ! -f "$f" ] || line=$(awk -F '\t' -v b="$board" -v s="$session" '$3 == b && $5 == s { print; exit }' "$f")
    if [ -z "$line" ]; then
      printf 'dispatch: no worker with the session %s on the board %s.\n' "$session" "$board" >&2
      exit 1
    fi
    IFS=$'\t' read -r _ mode _ report _ cwd name <<<"$line"
    if [ ! -d "$cwd" ]; then
      printf 'dispatch: %s is not a folder. The record stays.\n' "$cwd" >&2
      exit 2
    fi
    if [ "$mode" = auto ]; then
      readonly_rules "$cwd" >/dev/null || exit 2
    fi
    # The orchestrator that started the worker is gone: give the address of this one.
    prompt="The stop of the board orchestrator cut your turn. Continue the task. If you waited for an answer from the user, ask again."$'\n\n'"The orchestrator has a new address. After you write the report, run: hc send $HC_TERMINAL_ID \"report $name $report\""
    if ! addr=$(run_worker "$mode" "$board" "$cwd" "$name" "$session" "$report" "$prompt" --resume "$session") || [ -z "$addr" ]; then
      printf 'dispatch: hc did not start the worker.\n' >&2
      exit 1
    fi
    # shellcheck disable=SC2016 # An awk program.
    rewrite_workers '$3 == b && $5 == s { $1 = a } { print }' -v b="$board" -v s="$session" -v a="$addr"
    printf '%s\n%s\n' "$addr" "$report"
    ;;
  resume-clear)
    board="${2:?usage: dispatch.sh resume-clear BOARD [SESSION]}" only="${3:-}"
    f=$(workers_file)
    [ -f "$f" ] || exit 0
    tmp=$(mktemp "$f.XXXXXX")
    while IFS= read -r line; do
      if [ "$(cut -f3 <<<"$line")" = "$board" ] && { [ -z "$only" ] || [ "$(cut -f5 <<<"$line")" = "$only" ]; } &&
        ! live_session "$line"; then
        continue
      fi
      printf '%s\n' "$line"
    done <"$f" >"$tmp"
    mv "$tmp" "$f"
    ;;
  close)
    addr="${2:?usage: dispatch.sh close ADDRESS [wait]}"
    if ! json=$("${HC[@]}" get "$addr" --json 2>/dev/null) ||
      [ "$(jq -r '.labels["board.role"] // empty' <<<"$json")" != worker ]; then
      printf 'dispatch: no agent in %s.\n' "$addr" >&2
      exit 1
    fi
    session=$(jq -r '.labels["board.session"] // empty' <<<"$json")
    # A worker that exited is finished: remove its terminal and its record only.
    if [ "$(jq -r '.state' <<<"$json")" = live ]; then
      # hc wait also ends on a message to the caller (another worker reports): wait again
      # then. Without "wait", give up after the 90 s check-in or 20 messages.
      tries=20
      while :; do
        reason=$("${HC[@]}" wait "$addr" --timeout 90 2>/dev/null | jq -r '.reason // empty' 2>/dev/null) || reason=""
        [ "$(agent_state "$addr")" = working ] || break
        if [ "${3:-}" != wait ]; then
          if [ "$reason" != message ] || [ "$tries" -le 0 ]; then break; fi
          tries=$((tries - 1))
        fi
      done
      if [ "$(agent_state "$addr")" = working ]; then
        printf 'dispatch: the worker in %s is still working. Close nothing.\n' "$addr" >&2
        exit 1
      fi
      # The user gave the worker a pane: herdr-app keeps that terminal and puts a shell
      # in its place when claude ends. Park it first: no pane, no keep, no shell tab.
      if [ -n "$(jq -r '.labels["herdr.tab"] // empty' <<<"$json")" ]; then
        "${HAPP[@]}" "do" terminal.park --terminal "$addr" >/dev/null 2>&1 || true
      fi
      "${HC[@]}" kill "$addr" >/dev/null 2>&1 || true
    fi
    "${HC[@]}" rm "$addr" >/dev/null 2>&1 || true
    # shellcheck disable=SC2016 # An awk program.
    rewrite_workers '$1 != a { print }' -v a="$addr"
    # The card keeps the session ID: claude --resume <id> opens the worker again.
    printf '%s\n' "$session"
    ;;
  last)
    addr="${2:?usage: dispatch.sh last ADDRESS}"
    need_worker "$addr"
    session=$(hc_labels "$addr" | jq -r '.["board.session"] // empty')
    text=""
    if [ -n "$session" ]; then
      file=""
      for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$session.jsonl"; do
        [ ! -f "$f" ] || file=$f
      done
      if [ -n "$file" ]; then
        # The last assistant message with text. @json keeps a message on one line.
        text=$(jq -r 'select(.type == "assistant") | [.message.content[]? | select(.type == "text") | .text] | join("\n") | select(. != "") | @json' "$file" 2>/dev/null | tail -n 1 | jq -r . 2>/dev/null) || text=""
      fi
    fi
    if [ -n "$text" ]; then
      [ "${#text}" -le 3000 ] || text=${text: -3000}
      printf '%s\n' "$text"
    else
      "${HC[@]}" read "$addr" 2>/dev/null | tail -n 40 || true
    fi
    ;;
  remind)
    addr="${2:?usage: dispatch.sh remind ADDRESS REPORT}" report="${3:?usage: dispatch.sh remind ADDRESS REPORT}"
    need_worker "$addr"
    status=$(agent_state "$addr")
    case "$status" in
      idle | done) ;;
      *)
        printf 'dispatch: the worker is working (%s). Send nothing.\n' "${status:-unknown}" >&2
        exit 1
        ;;
    esac
    if ! "${HC[@]}" send "$addr" "Write the report again to $report now, in one Write call. Give the full report for the current state, with a new first line in the same form as before. The new report replaces the old one." >/dev/null; then
      printf 'dispatch: could not send to the worker in %s.\n' "$addr" >&2
      exit 1
    fi
    ;;
  answer)
    addr="${2:?usage: dispatch.sh answer ADDRESS FILE}" file="${3:?usage: dispatch.sh answer ADDRESS FILE}"
    if [ ! -s "$file" ]; then
      printf 'dispatch: the answer file %s is missing or empty.\n' "$file" >&2
      exit 2
    fi
    need_worker "$addr"
    status=$(agent_state "$addr")
    # Text sent into a permission prompt can select an option: send only to an idle or
    # done worker.
    case "$status" in
      idle | done) ;;
      *)
        printf 'dispatch: the worker is %s. Send nothing.\n' "${status:-unknown}" >&2
        exit 1
        ;;
    esac
    if ! "${HC[@]}" send "$addr" "The user answers through the orchestrator:"$'\n\n'"$(<"$file")" >/dev/null; then
      printf 'dispatch: could not send to the worker in %s.\n' "$addr" >&2
      exit 1
    fi
    ;;
  *)
    printf 'usage: dispatch.sh start|workers|resumable|resume|resume-clear|close|last|remind|answer|policy|policy-set|report|run-add|note-add|log|inbox-clear ...\n' >&2
    exit 2
    ;;
esac
