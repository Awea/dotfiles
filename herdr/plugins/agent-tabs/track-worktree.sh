#!/usr/bin/env bash
# Claude Code hook: record the git worktree of the most recent work of claude in the
# Herdr pane. The reviewr action opens reviewr for that worktree. Also record the start
# of each turn, so that the reviewr scope "last turn" shows the turn.
#
#   track-worktree.sh start    SessionStart hook: delete the files of the pane, but not
#                              after a compact, a resume or a fork
#   track-worktree.sh end      SessionEnd hook: delete the files of the pane
#   track-worktree.sh tool     PostToolUse hook for Edit, Write, MultiEdit, NotebookEdit
#                              and Bash, also in subagents
#   track-worktree.sh prompt   UserPromptSubmit hook: snapshot the worktrees of the turn
#   track-worktree.sh pre      PreToolUse hook, same matcher as tool: snapshot a new
#                              worktree of the turn
#   track-worktree.sh stop     Stop hook: write the turn start as the reviewr turn base
#
# `make links` links the script as ~/.claude/hooks/herdr-worktree.sh.
#
# The hook finds the candidate folders, the newest first: the folder of the edited
# file, or the cd and git -C targets of a Bash command, the last one first. Without a
# valid target, the hook cwd is the candidate, but only when it is not in the worktree
# of the project dir.
# Claude Code puts the Bash folder back to the project dir after a cd out of the
# project, so most commands without cd run in the main repo. They must not replace a
# linked worktree where claude works. The hook keeps the first candidate in the same
# repo as the session, and writes its worktree root.
#
# reviewr shows "last turn" as the diff against the tree in the ref
# refs/worktree/reviewr/turn-base. reviewr writes it only while a reviewr pane is open.
# The hooks write it also when no pane is open. A snapshot is a tree of the files in the
# worktree, as reviewr makes it. The prompt mode writes a snapshot of the recorded
# worktree and of the cwd worktree to the turn file. The pre mode adds a snapshot of
# each other worktree where the turn works. The stop mode writes the turn base for each
# worktree that the turn changed. Like reviewr, a turn that changes no file keeps the
# old turn base. The stop mode then deletes the turn file, so a second Stop in the same
# turn does nothing. Claude Code runs no Stop after an Esc, so the prompt mode first
# ends a turn that still has its file.
#
# The hook never stops claude: it always exits 0 and writes nothing on stdout.
set -uo pipefail
exec >/dev/null
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

input=$(cat 2>/dev/null) || input=""
[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0
file=$(worktree_file "$HERDR_PANE_ID")
turns=$(turn_file "$HERDR_PANE_ID")
mode="${1:-}"

# The snapshot uses a temporary index in the git dir. Remove it and its lock on exit,
# also when the hook gets a signal, for example at its time limit.
tmp_index=""
trap '[ -z "$tmp_index" ] || rm -f "$tmp_index" "$tmp_index.lock"' EXIT
trap 'exit 0' TERM INT HUP

# Print the worktree root of folder $1, or nothing outside a git repo.
toplevel() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || true
}

# Make a snapshot of worktree $1: the tree of all its files, also the untracked files
# that git does not ignore. Put the tree in the variable tree, and return 1 on failure.
# Do not call it in $(...): the EXIT trap must see tmp_index. A temporary index, seeded
# from the real index, lets git skip the unchanged files. The real index, the files and
# the refs do not change.
snapshot() {
  local dir
  tree=""
  dir=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  tmp_index="$dir/agent-tabs-turn-index.$$"
  rm -f "$tmp_index" "$tmp_index.lock"
  if [ ! -f "$dir/index" ] || cp "$dir/index" "$tmp_index" 2>/dev/null; then
    GIT_INDEX_FILE=$tmp_index git -C "$1" add -A 2>/dev/null &&
      tree=$(GIT_INDEX_FILE=$tmp_index git -C "$1" write-tree 2>/dev/null)
  fi
  rm -f "$tmp_index" "$tmp_index.lock"
  tmp_index=""
  [ -n "$tree" ]
}

# End the turn of the turn file: for each worktree that the turn changed, write its
# start as the reviewr turn base. Use only the first line of each worktree, because two
# pre hooks at the same time can add the same worktree.
end_turn() {
  local root start
  [ -f "$turns" ] || return 0
  while IFS=$'\t' read -r root start; do
    if [ -z "$start" ] || [ ! -d "$root" ]; then continue; fi
    snapshot "$root" || continue
    [ "$tree" = "$start" ] || git -C "$root" update-ref refs/worktree/reviewr/turn-base "$start" 2>/dev/null
  done < <(awk -F '\t' '!seen[$1]++' "$turns")
}

# Write the text $2 to file $1 in one step. Write nothing on failure.
write_file() {
  mkdir -p "$(dirname "$1")" 2>/dev/null || return 0
  printf '%s' "$2" >"$1.tmp.$$" 2>/dev/null && mv -f "$1.tmp.$$" "$1" 2>/dev/null
  rm -f "$1.tmp.$$"
}

case "$mode" in
  start)
    # A compact, a resume or a fork keeps the work of the session, so keep its record.
    case "$(jq -r '.source // ""' <<<"$input" 2>/dev/null)" in
      compact | resume | fork) ;;
      *) rm -f "$file" "$turns" ;;
    esac
    exit 0
    ;;
  end)
    rm -f "$file" "$turns"
    exit 0
    ;;
  prompt)
    # Claude Code runs no Stop hook after an Esc. End that turn here.
    end_turn
    cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null) || cwd=""
    dirs=()
    [ ! -f "$file" ] || dirs=("$(head -n 1 "$file")")
    dirs+=("$cwd")
    text="" seen=$'\n'
    for dir in "${dirs[@]}"; do
      [ -d "$dir" ] || continue
      root=$(toplevel "$dir")
      [ -n "$root" ] || continue
      [[ "$seen" != *$'\n'"$root"$'\n'* ]] || continue
      seen+="$root"$'\n'
      snapshot "$root" || continue
      text+="$root"$'\t'"$tree"$'\n'
    done
    if [ -n "$text" ]; then write_file "$turns" "$text"; else rm -f "$turns"; fi
    exit 0
    ;;
  stop)
    end_turn
    rm -f "$turns"
    exit 0
    ;;
  tool | pre) ;;
  *) exit 0 ;;
esac

IFS=$'\x1f' read -r cwd tool path < <(jq -r '[.cwd // "", .tool_name // "",
  .tool_input.file_path // .tool_input.notebook_path // ""] | join("\u001f")' <<<"$input" 2>/dev/null) || exit 0
[ -n "$cwd" ] || exit 0

# Print the cd and git -C targets of the Bash command $1, one "cd TARGET" or
# "C TARGET" line for each, in the order of the command. One awk program reads the
# command once, so a long command stays fast. To find only real commands, it:
# 1. Removes \\, \" and \'. An escaped quote then does not open or close a string.
# 2. Removes the heredoc bodies. It does not see a second heredoc on the same line,
#    for example "cmd <<E1 <<E2".
# 3. Removes the # comments. Replaces each quoted string with "" unless it comes
#    directly after cd or -C, as a quoted path does.
# 4. Splits the text into commands at ; & | ( and newlines, and keeps the commands
#    that start with cd or git ... -C.
bash_targets() {
  awk "$(cat <<'AWK'
BEGIN { RS = "\001" }
{
  t = $0
  gsub(/\\\\|\\"|\\'/, "", t)

  # Step 2: keep the lines outside the heredoc bodies. "<<<" is a here-string.
  n = split(t, lines, "\n"); t = ""; word = ""
  for (k = 1; k <= n; k++) {
    line = lines[k]
    if (word != "") {
      sub(/^\t+/, "", line)
      if (line == word) word = ""
      continue
    }
    t = t line "\n"
    if (match(line, /(^|[^<])<<-?[ \t]*["']?[A-Za-z_][A-Za-z0-9_]*/)) {
      word = substr(line, RSTART, RLENGTH)
      sub(/^[^<]?<<-?[ \t]*["']?/, "", word)
    }
  }

  # Step 3: one pass over the characters.
  out = ""; n = length(t); i = 1
  while (i <= n) {
    c = substr(t, i, 1)
    if (c == "\"" || c == "'") {
      j = index(substr(t, i + 1), c); if (j == 0) j = n - i + 1
      tail = substr(out, length(out) - 9)
      if (tail ~ /(^|[ \t\n])(cd|-C)[ \t]+$/ || tail ~ /(^|[ \t\n])cd[ \t]+--[ \t]+$/)
        out = out c substr(t, i + 1, j - 1) c
      else
        out = out "\"\""
      i += j + 1
    } else if (c == "#" && (out == "" || substr(out, length(out)) ~ /[ \t\n;&|(]/)) {
      j = index(substr(t, i), "\n"); if (j == 0) break
      i += j - 1
    } else {
      out = out c; i++
    }
  }

  # Step 4: print the targets.
  n = split(out, cmds, /[;&|(\n]/)
  for (k = 1; k <= n; k++) {
    cmd = cmds[k]; sub(/^[ \t]+/, "", cmd)
    if (match(cmd, /^cd[ \t]+(--[ \t]+)?/)) kind = "cd"
    else if (match(cmd, /^git([ \t]+(-c[ \t]+[^ \t]+|--[a-z-]+))*[ \t]+-C[ \t]+/)) kind = "C"
    else continue
    rest = substr(cmd, RLENGTH + 1)
    if (match(rest, /^"[^"]*"|^'[^']*'|^[^ \t]+/)) print kind " " substr(rest, 1, RLENGTH)
  }
}
AWK
)" <<<"$1"
}

candidates=()
case "$tool" in
  Edit | Write | MultiEdit | NotebookEdit)
    [ -n "$path" ] || exit 0
    [[ "$path" == /* ]] || path="$cwd/$path"
    dir=$(dirname "$path")
    while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname "$dir"); done
    candidates=("$dir")
    ;;
  Bash)
    command=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null) || exit 0
    # A command without cd and -C has no target. Skip the scan.
    if [[ "$command" != *cd* && "$command" != *-C* ]]; then command=""; fi
    # Resolve each target against the folder of the previous cd. git -C does not
    # change the folder. Put the newest target first.
    cur=$cwd
    while read -r kind t; do
      case "$t" in
        \"*\") t=${t:1:-1} ;;
        \'*\') t=${t:1:-1} ;;
      esac
      [[ "$t" != *'$'* ]] || continue
      case "$t" in
        \~) t=$HOME ;;
        \~/*) t="$HOME/${t:2}" ;;
        /*) ;;
        *) t="$cur/$t" ;;
      esac
      [ -d "$t" ] || continue
      candidates=("$t" "${candidates[@]}")
      [ "$kind" != cd ] || cur=$t
    done < <(bash_targets "$command")
    if [ "${#candidates[@]}" -eq 0 ] && [ "$(toplevel "$cwd")" != "$(toplevel "${CLAUDE_PROJECT_DIR:-}")" ]; then
      candidates=("$cwd")
    fi
    ;;
  *) exit 0 ;;
esac

common=$(git -C "${CLAUDE_PROJECT_DIR:-$cwd}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
for dir in "${candidates[@]}"; do
  c=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  [ -z "$common" ] || [ "$c" = "$common" ] || continue
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
  if [ "$mode" = tool ]; then
    write_file "$file" "$root"$'\n'
  elif ! cut -f 1 "$turns" 2>/dev/null | grep -qxF -- "$root" && snapshot "$root"; then
    # The turn works in a worktree that the prompt mode did not see. Add its snapshot.
    mkdir -p "$(dirname "$turns")" 2>/dev/null && printf '%s\t%s\n' "$root" "$tree" >>"$turns"
  fi
  exit 0
done
exit 0
