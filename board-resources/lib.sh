# shellcheck shell=bash
# Board resources: map a folder to its board, and find the files of a board.
# Config: $BOARD_RESOURCES_HOME/<board>/{roots,databases,notebooks,mcp.json,settings.json}.
# The config names private projects, so it stays out of the dotfiles. It is in the vault,
# which syncs it to each machine: $OBSIDIAN_VAULT_PATH/_board-resources. With no
# OBSIDIAN_VAULT_PATH, the vault path comes from the env of the Claude settings. With no
# vault, the config is in ~/.config/board-resources.

# default_home: the config folder when BOARD_RESOURCES_HOME is not set.
default_home() {
  local vault=${OBSIDIAN_VAULT_PATH:-}
  if [ -z "$vault" ] && [ -f "$HOME/.claude/settings.json" ]; then
    vault=$(jq -r '.env.OBSIDIAN_VAULT_PATH // empty' "$HOME/.claude/settings.json" 2>/dev/null) || vault=""
  fi
  if [ -n "$vault" ]; then
    printf '%s\n' "$vault/_board-resources"
  else
    printf '%s\n' "$HOME/.config/board-resources"
  fi
}

BOARD_RESOURCES_HOME="${BOARD_RESOURCES_HOME:-$(default_home)}"

# expand_path PATH: PATH with a leading ~ replaced by $HOME.
expand_path() {
  # shellcheck disable=SC2088 # A literal ~ in the config.
  case $1 in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "$HOME/${1#'~/'}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# real_dir DIR: the real path of the folder DIR. Exit 1 when it is not a folder.
real_dir() {
  (cd -- "$1" 2>/dev/null && pwd -P)
}

# board_of DIR: print the board whose root holds DIR (the longest root wins). Exit 1 when
# no board holds DIR. The claude wrapper runs it at each start: it resolves each root line
# once (a glob root: only its parent folder), not each folder that the glob matches.
board_of() {
  local dir roots board line root parent pattern real rest part match best="" best_len=0
  dir=$(real_dir "$1") || return 1
  for roots in "$BOARD_RESOURCES_HOME"/*/roots; do
    [ -f "$roots" ] || continue
    board=${roots%/roots}
    board=${board##*/}
    while IFS= read -r line || [ -n "$line" ]; do
      case $line in '' | '#'*) continue ;; esac
      # shellcheck disable=SC2088 # A literal ~ in the config.
      case $line in '~') root=$HOME ;; '~/'*) root="$HOME/${line#'~/'}" ;; *) root=$line ;; esac
      pattern=${root##*/}
      case $pattern in
        *[*?[]*)
          # A glob on the last part: DIR must be under the real parent, in a folder whose
          # name matches the glob.
          parent=${root%/*}
          real=$(real_dir "${parent:-/}") || continue
          rest=${dir#"$real"/}
          [ "$rest" != "$dir" ] || continue
          part=${rest%%/*}
          # shellcheck disable=SC2053 # The glob of the config.
          [[ $part == $pattern ]] || continue
          match="$real/$part"
          ;;
        *)
          match=$(real_dir "$root") || continue
          [ "$dir" = "$match" ] || [ "${dir#"$match"/}" != "$dir" ] || continue
          ;;
      esac
      if [ "${#match}" -gt "$best_len" ]; then
        best=$board best_len=${#match}
      fi
    done <"$roots"
  done
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

# board_file BOARD NAME: print the path of the file NAME of BOARD. Exit 1 when it does not
# exist.
board_file() {
  local f="$BOARD_RESOURCES_HOME/$1/$2"
  [ -f "$f" ] || return 1
  printf '%s\n' "$f"
}

# board_notebooks BOARD: print the notebooks folder of BOARD. Exit 1 when it has none.
board_notebooks() {
  local f line
  f=$(board_file "$1" notebooks) || return 1
  line=$(grep -vE '^[[:space:]]*(#|$)' "$f" | head -n 1) || return 1
  [ -n "$line" ] || return 1
  expand_path "$line"
}

# with_timeout SECS CMD...: run CMD, stop it and its children with TERM after SECS
# seconds. Exit 124 on a time-out, else the exit of CMD. Pure bash: macOS has no timeout
# command.
with_timeout() {
  local secs=$1 pid watcher status=0 m=${-//[^m]/}
  shift
  # Job control puts CMD in its own process group: the TERM also stops its children, so
  # no child keeps an output pipe open.
  set -m
  "$@" &
  pid=$!
  [ -n "$m" ] || set +m
  # The watcher kills its sleep when it gets TERM, so no sleep keeps an output open.
  (
    trap 'kill "$s" 2>/dev/null; exit 0' TERM
    sleep "$secs" &
    s=$!
    wait "$s"
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    exit 1
  ) >/dev/null 2>&1 &
  watcher=$!
  wait "$pid" || status=$?
  if kill -0 "$watcher" 2>/dev/null; then
    kill -TERM "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null || true
    return "$status"
  fi
  # The watcher exits 1 after it sent TERM.
  if wait "$watcher" 2>/dev/null; then return "$status"; fi
  return 124
}
