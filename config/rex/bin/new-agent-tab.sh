#!/usr/bin/env bash
# ctrl+b a in Renux: ask a prompt, an effort and the focus, then start claude in a new tab
# of SESSION. In a linked git worktree, claude starts in the main checkout. The Rex config
# runs this script in a floating pane, which closes when the script ends.
#
#   new-agent-tab.sh DIR SESSION BLOCK CLIENT
set -euo pipefail
dir=$1 session=$2
here=$(dirname "$(readlink -f "$0")")
folders="$here/folders.sh"

folder=$(bash "$folders" main-folder "$dir" 2>/dev/null) || folder=$dir

printf '\e[1mNew claude tab\e[0m in %s   (ctrl+c closes)\n\n' "${folder/#$HOME/~}"
read -r -e -p 'Prompt (Enter for a clean tab): ' prompt

# key: one key press. Escape closes the popup.
key() {
  local k
  IFS= read -rsn1 k
  [[ $k == $'\e' ]] && exit 0
  printf '%s' "$k"
}

printf 'Effort [l]ow [m]edium [h]igh [x]high [M]ax (Enter for default) '
effort=
while :; do
  case $(key) in
    l) effort=low ;; m) effort=medium ;; h) effort=high ;; x) effort=xhigh ;; M) effort=max ;;
    "") ;;
    *) continue ;;
  esac
  break
done
printf '%s\n' "${effort:-default}"

printf 'Focus the new tab? [y/N] '
focus=false
while :; do
  case $(key) in
    y) focus=true ;;
    n | "") ;;
    *) continue ;;
  esac
  break
done
printf '%s\n' "$focus"

argv=(claude)
[[ -n $effort ]] && argv+=(--effort "$effort")
[[ -n $prompt ]] && argv+=("$prompt")
rex window new -s "$session" --cwd "$folder" --focus="$focus" -- "${argv[@]}" >/dev/null
