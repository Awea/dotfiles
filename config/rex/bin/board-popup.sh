# shellcheck shell=bash
# The shared code of board-open.sh and board-stop.sh, the Renux popups of the board
# orchestrator. Source this file. The Rex config runs the popup script in a floating pane,
# which closes when the script ends. Escape closes it. After an error, the pane waits for
# one key.

# popup_fail MESSAGE: show MESSAGE, wait for one key, then exit 1.
popup_fail() {
  printf '%s\n(press a key)' "$1"
  IFS= read -rsn1 _ || true
  exit 1
}

# popup_first_line FILE DEFAULT: the first line of FILE that has text, else DEFAULT.
popup_first_line() { grep -m1 . "$1" || printf '%s' "$2"; }

# board_popup TITLE VERB SUBCOMMAND FILTER EMPTY AUTO CLIENT
#   TITLE       the title of the popup
#   VERB        the board.sh command to run on the picked board (open or stop), and the
#               word that the popup shows with it (Opening or Stopping)
#   SUBCOMMAND  the board.sh command that gives the JSON list (boards or running)
#   FILTER      the jq filter that turns the JSON into lines "KEY<tab>BOARD"
#   EMPTY       the text to show when the list is empty
#   AUTO        yes: with one board in the list, use it at once, with no key press
#   CLIENT      the Rex client, for board.sh
board_popup() {
  local title=$1 verb=$2 sub=$3 filter=$4 empty=$5 auto=$6
  local board_sh=${BOARD_SH:-$HOME/.claude/skills/board-orchestrator/board.sh}
  local errf json lines k b i doing pick=''
  export REX_CLIENT=${7:-}
  # board.sh takes the backend of the caller from the env. A popup is always Renux.
  export BOARD_TERM=rex
  case $verb in open) doing=Opening ;; *) doing=Stopping ;; esac

  printf '\e[1m%s\e[0m   (Esc closes)\n\n' "$title"

  # The error text goes to a file, not a pipe: a child of board.sh that keeps stderr open
  # would make a $(...) wait for it.
  errf=$(mktemp)
  trap 'rm -f "$errf"' EXIT

  # The board.sh list command is fast, so the list shows at once.
  json=$(bash "$board_sh" "$sub" 2>"$errf") ||
    popup_fail "$(popup_first_line "$errf" "board.sh $sub failed.")"
  lines=$(jq -r "$filter" <<<"$json" 2>"$errf") ||
    popup_fail "$(popup_first_line "$errf" "jq failed on the output of board.sh $sub.")"

  local keys=() names=()
  while IFS=$'\t' read -r k b; do
    [[ -n $k ]] || continue
    keys+=("$k") names+=("$b")
  done <<<"$lines"

  if [[ ${#keys[@]} -eq 0 ]]; then
    printf '%s\n' "$empty"
    IFS= read -rsn1 _ || true
    exit 0
  fi

  if [[ $auto == yes && ${#keys[@]} -eq 1 ]]; then
    pick=${names[0]}
  else
    for i in "${!keys[@]}"; do printf '[%s] %s\n' "${keys[$i]}" "${names[$i]}"; done
    while [[ -z $pick ]]; do
      IFS= read -rsn1 k || exit 0
      [[ $k == $'\e' ]] && exit 0
      for i in "${!keys[@]}"; do
        [[ ${keys[$i]} == "$k" ]] && pick=${names[$i]}
      done
    done
  fi

  printf '\n%s %s…\n' "$doing" "$pick"
  bash "$board_sh" "$verb" "$pick" >/dev/null 2>"$errf" ||
    popup_fail "$(popup_first_line "$errf" "board.sh $verb $pick failed.")"
  exit 0
}
