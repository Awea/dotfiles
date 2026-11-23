# shellcheck shell=bash
# Shared functions of multica-perso: read the vault cards (read only, with the
# board-orchestrator board-scan.sh) and the Multica issues (with the multica CLI).
# MULTICA_BIN is the multica command (default multica). OBSIDIAN_VAULT_PATH is the vault.

mp_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# The vault path: OBSIDIAN_VAULT_PATH, else the env of ~/.claude/settings.json (as the
# board-orchestrator does). Return 1 when there is none.
mp_vault() {
  local path=${OBSIDIAN_VAULT_PATH:-}
  if [ -z "$path" ] && [ -f "$HOME/.claude/settings.json" ]; then
    path=$(jq -r '.env.OBSIDIAN_VAULT_PATH // empty' "$HOME/.claude/settings.json" 2>/dev/null) || path=""
  fi
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# The path of the board-orchestrator board-scan.sh of this repo.
mp_board_scan() { printf '%s\n' "$mp_repo/claude/skills/board-orchestrator/board-scan.sh"; }

# mp_cli ARGS...: run the multica CLI. On a failure, tell which call failed and return 1.
mp_cli() {
  if ! "${MULTICA_BIN:-multica}" "$@"; then
    printf 'multica-perso: multica %s failed\n' "$*" >&2
    return 1
  fi
}

# mp_vault_cards BOARD: one JSON line per open card of the board:
# {line, column, priority, title, project, repo, context, key, recurring, date}. project is the
# project note name or null, repo its folder or null, context the context lines with no
# leading tab, key the Multica key of the context ("in Multica PER-3") or null.
mp_vault_cards() {
  bash "$(mp_board_scan)" card "$1" '' | jq -c '
    select(.column)
    | (.context_line | split("\n") | map(sub("^\t"; "")) | join("\n")) as $context
    | {line, column, priority, title,
       project: (if .project then (.project | sub("^Projects/"; "") | sub("\\.md$"; "")) else null end),
       repo, context: $context,
       key: ($context | capture("in Multica (?<k>[A-Z][A-Z0-9]*-[0-9]+)").k // null),
       recurring, date}'
}

# mp_issues: one JSON line per issue of the current workspace, all pages.
mp_issues() {
  local offset=0 page count
  while :; do
    page=$(mp_cli issue list --output json --limit 100 --offset "$offset" \
      --fields id,identifier,title,description,status,priority,assignee_type,project_id,metadata,updated_at) || return 1
    # Accept the object of the CLI or a bare array, and fail on another shape: an empty
    # list would make import duplicate all issues and export empty the mirror.
    page=$(jq -c 'if type == "array" then {issues: ., has_more: false}
      elif (.issues | type) == "array" then . else error("x") end' <<<"$page" 2>/dev/null) || {
      printf 'multica-perso: unknown issue list shape from multica issue list\n' >&2
      return 1
    }
    jq -c '.issues[]' <<<"$page"
    count=$(jq '.issues | length' <<<"$page")
    if [ "$(jq -r '.has_more // false' <<<"$page")" != true ] || [ "$count" -eq 0 ]; then break; fi
    offset=$((offset + count))
  done
}

# mp_projects: one JSON line {id, title} per project.
mp_projects() {
  local out
  out=$(mp_cli project list --output json) || return 1
  jq -c 'if type == "array" then . else .projects end | .[] | {id, title}' <<<"$out"
}

mp_status_of() {
  case "$1" in
    '📥 Backlog') echo backlog ;;
    '📋 This Week') echo todo ;;
    '🔨 In Progress') echo in_progress ;;
    '⏳ Waiting On') echo blocked ;;
    *) return 1 ;;
  esac
}

# The column of a status. Empty for cancelled: the mirror does not show it.
mp_column_of() {
  case "$1" in
    backlog) echo '📥 Backlog' ;;
    todo) echo '📋 This Week' ;;
    in_progress) echo '🔨 In Progress' ;;
    blocked | in_review) echo '⏳ Waiting On' ;;
    done) echo '✅ Done' ;;
    *) echo '' ;;
  esac
}

mp_priority_of() {
  case "$1" in
    🔴) echo urgent ;;
    🟠) echo high ;;
    🟡) echo medium ;;
    🟢) echo low ;;
    *) echo none ;;
  esac
}

mp_emoji_of() {
  case "$1" in
    urgent) echo 🔴 ;;
    high) echo 🟠 ;;
    medium) echo 🟡 ;;
    low) echo 🟢 ;;
    *) echo '' ;;
  esac
}
