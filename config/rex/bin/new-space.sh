#!/usr/bin/env bash
# ctrl+b shift+n in Renux: pick a frequent folder, then open a space (a Rex session) there.
# Enter: a shell, shown at once. Tab: ask a prompt, an effort and the focus, then start
# claude in the space. The Rex config runs this script in a floating pane, which closes
# when the script ends.
#
#   new-space.sh DIR SESSION BLOCK CLIENT
set -euo pipefail
client=${4:-}
here=$(dirname "$(readlink -f "$0")")
agent_tabs="$here/../../../herdr-app/bin/agent-tabs.sh"

# show JSON: make Renux show the new session. JSON is the output of rex new --json.
# Renux switches the session only when the call gives its session_id.
show() {
  [[ -n $client ]] || return 0
  rex -C "$client" do session.select \
    --args "$(jq -c '{session_id, window_id: .initial_windows[0].window_id}' <<<"$1")" >/dev/null
}

# key: one key press. Escape closes the popup.
key() {
  local k
  IFS= read -rsn1 k
  [[ $k == $'\e' ]] && exit 0
  printf '%s' "$k"
}

picked=$(bash "$agent_tabs" folders | jq -r '.[]' | sed "s|^$HOME|~|" |
  fzf --expect=tab --layout=reverse --prompt='New space> ' \
    --header='Enter: shell · Tab: claude · Esc: close') || exit 0
how=$(sed -n 1p <<<"$picked")
dir=$(sed -n 2p <<<"$picked")
[[ -n $dir ]] || exit 0
dir=${dir/#\~/$HOME}

if [[ $how != tab ]]; then
  show "$(rex new "${dir##*/}" --cwd "$dir" --json)"
  exit 0
fi

printf '\e[1mNew space with claude\e[0m in %s   (ctrl+c closes)\n\n' "${dir/#$HOME/~}"
read -r -e -p 'Prompt (Enter for a clean claude): ' prompt
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
printf 'Focus the new space? [y/N] '
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
created=$(rex new "${dir##*/}" --cwd "$dir" --json -- "${argv[@]}")
[[ $focus == false ]] || show "$created"
