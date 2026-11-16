# shellcheck shell=bash
# Shared helpers for the board-orchestrator scripts. Source this file, do not run it.

# herdr-app mods run commands with a small PATH. Add the system paths for jq and hc. On
# macOS, Homebrew puts jq and bash 5 in /opt/homebrew/bin (Apple silicon) or
# /usr/local/bin. The hc installer puts hc in ~/.local/bin.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# /bin/bash on macOS is bash 3.2. When a script that sources this file runs under bash
# 3.2, run it again with the bash in PATH if that bash is newer.
# shellcheck disable=SC2016 # The other bash expands BASH_VERSINFO.
if [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ "${BASH_SOURCE[1]:-}" = "$0" ] &&
  "$(command -v bash)" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null; then
  # ${1+"$@"}: bash 3.2 with set -u stops on "$@" when there is no argument.
  exec "$(command -v bash)" "$0" ${1+"$@"}
fi

# The tests point these at fakes.
HC=("${HC_BIN:-hc}")
# shellcheck disable=SC2034 # Used by the scripts that source this file.
HAPP=("${HERDR_APP_BIN:-herdr-app}")

# The state folder: the worker and orchestrator records, and the report files.
state_dir() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/board-orchestrator-hc"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# hc_labels ADDR: the labels (a JSON object) of a live hc terminal. Exit 1 when the
# terminal is gone or finished.
hc_labels() {
  local json
  json=$("${HC[@]}" get "$1" --json 2>/dev/null) || return 1
  jq -e '.state == "live"' <<<"$json" >/dev/null 2>&1 || return 1
  jq -c '.labels // {}' <<<"$json"
}

# has_labels ADDR BOARD ROLE: exit 0 when the live terminal ADDR belongs to BOARD with
# that role. A recorded address can be gone, or can belong to another terminal now.
has_labels() {
  local labels
  labels=$(hc_labels "$1") || return 1
  jq -e --arg b "$2" --arg r "$3" '.board == $b and .["board.role"] == $r' \
    <<<"$labels" >/dev/null 2>&1
}

# board_slug NAME: a short lowercase name of a-z, 0-9 and -, as agent_slug of agent-tabs.
board_slug() {
  local text
  text=$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs 'a-z0-9' '-')
  text=$(sed 's/^[^a-z]*//; s/-*$//' <<<"$text")
  if [ "${#text}" -gt 30 ]; then
    text="${text:0:30}"
    [[ "$text" != *-* ]] || text="${text%-*}"
  fi
  printf '%s\n' "$text"
}

# new_uuid: a lowercase UUID. uuidgen prints uppercase on macOS.
new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}

read_settings() {
  local out
  if [ ! -e "$1" ]; then
    printf '{}\n'
    return
  fi
  if ! out=$(jq -cs 'if length == 0 then {} elif length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' "$1" 2>/dev/null) || [ -z "$out" ]; then
    printf 'dispatch: %s is not valid JSON.\n' "$1" >&2
    exit 2
  fi
  printf '%s\n' "$out"
}

# vault_path: the vault folder, from OBSIDIAN_VAULT_PATH or the Claude settings.
vault_path() {
  local path=${OBSIDIAN_VAULT_PATH:-}
  if [ -z "$path" ] && [ -f "$HOME/.claude/settings.json" ]; then
    path=$(jq -r '.env.OBSIDIAN_VAULT_PATH // empty' "$HOME/.claude/settings.json" 2>/dev/null) || path=""
  fi
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

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

# project_repo NOTE: the repo: folder of the project note NOTE, with ~/ expanded. Print
# nothing when the note or the folder does not exist.
project_repo() {
  local repo
  [ -f "$1" ] || return 0
  repo=$(fm repo "$1")
  [[ "$repo" != \~/* ]] || repo="$HOME/${repo#"~/"}"
  [ -z "$repo" ] || [ ! -d "$repo" ] || printf '%s\n' "$repo"
}

# push_policy CWD: deny, ask, allow or missing, from the git push rules of the repo.
push_policy() {
  local cwd="$1" f kind json
  local -a files=()
  if [ ! -d "$cwd" ]; then
    printf 'dispatch: %s is not a folder.\n' "$cwd" >&2
    exit 2
  fi
  for f in "$cwd/.claude/settings.json" "$cwd/.claude/settings.local.json"; do
    json=$(read_settings "$f") || exit 2
    files+=("$json")
  done
  for kind in deny ask allow; do
    for json in "${files[@]}"; do
      if [ "$(jq -r --arg k "$kind" \
        '[(.permissions | objects | .[$k]) // [] | arrays | .[] | strings | select(startswith("Bash(git push"))] | length > 0' \
        <<<"$json")" = true ]; then
        printf '%s\n' "$kind"
        return
      fi
    done
  done
  printf 'missing\n'
}
