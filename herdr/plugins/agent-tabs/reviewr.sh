#!/usr/bin/env bash
# Action reviewr: open a reviewr pane right of the focused pane, for the git worktree of
# the most recent work of claude in that pane. The tab zooms on reviewr.
#
#   reviewr.sh             action: prefix+d runs it
#   reviewr.sh base ROOT   worker: set the target branch of reviewr from the pull request
#
# reviewr reads the turn base ref only when its pane starts, unless claude works in the
# worktree of the pane. So the action records the turn base of each pane that it opens.
# When the action zooms on a reviewr with an older turn base, and claude works in another
# worktree, it shows a toast. It never closes a reviewr: the comments that reviewr did
# not send are only in its memory.
#
# The hook track-worktree.sh records the worktree of each pane. Without a record, or
# when the recorded folder no longer exists, the action uses the cwd of the pane.
#
# The reviewr action "open" allows one reviewr in each workspace and uses the cwd of the
# focused pane. This action opens one next to the pane. When the tab already has one for
# the same worktree, the action zooms on it. When the focused pane is a reviewr, the
# action does nothing.
#
# reviewr diffs against its target branch: the pick ref of the worktree, else the
# default branch of the repo. reviewr reads the pick again at each refresh. Before the
# pane opens, the action writes the branch of the reflog as the pick, when no pick
# exists. The worker then writes the base branch of the pull request. It replaces the
# pick of the reflog and a pick from the reviewr picker.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$here/lib.sh"

pick_ref=refs/worktree/reviewr/base-pick
log="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr/plugins/awea.agent-tabs}/reviewr.log"

# Print the path of the file that holds the turn base of reviewr pane $1 at its start.
reviewr_file() {
  printf '%s\n' "$HOME/.local/state/herdr/plugins/awea.agent-tabs/reviewr/${1//:/_}"
}

# Print the turn base of worktree $1, or nothing without the ref.
turn_base() {
  git -C "$1" rev-parse --verify --quiet refs/worktree/reviewr/turn-base 2>/dev/null || true
}

# Start the worker that writes the target branch of worktree $1. Return at once.
start_worker() {
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  setsid -f bash "$here/reviewr.sh" base "$1" </dev/null >>"$log" 2>&1
}

# Print the default branch of the repo of folder $1, as reviewr finds it: the target of
# origin/HEAD, else init.defaultBranch, main or master when such a branch exists. Print
# nothing when no default exists.
default_branch() {
  local name
  name=$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || name=""
  name=${name#refs/remotes/origin/}
  if [ -n "$name" ]; then
    # A dangling origin/HEAD gives no default. Try the next names.
    git -C "$1" rev-parse --verify --quiet "refs/remotes/origin/$name^{commit}" >/dev/null || name=""
  elif oid=$(git -C "$1" rev-parse --verify --quiet "refs/remotes/origin/HEAD^{commit}" 2>/dev/null); then
    # A plain origin/HEAD, not a symbolic ref: use the first origin branch at its commit.
    name=$(git -C "$1" for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin |
      awk -v oid="$oid" '$2 != "refs/remotes/origin/HEAD" && $1 == oid {
        print substr($2, length("refs/remotes/origin/") + 1); exit }')
  fi
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
    return 0
  fi
  for name in "$(git -C "$1" config --get init.defaultBranch 2>/dev/null)" main master; do
    [ -n "$name" ] || continue
    if git -C "$1" show-ref --quiet --verify "refs/remotes/origin/$name" ||
      git -C "$1" show-ref --quiet --verify "refs/heads/$name"; then
      printf '%s\n' "$name"
      return 0
    fi
  done
}

# Write branch $2 as the pick of worktree $1, as reviewr does. For the default branch,
# delete the pick, so reviewr uses the default branch.
write_pick() {
  local blob
  if [ "$2" = "$(default_branch "$1")" ]; then
    git -C "$1" update-ref -d "$pick_ref"
    return
  fi
  blob=$(printf '%s' "$2" | git -C "$1" hash-object -w --stdin) || return 1
  git -C "$1" update-ref "$pick_ref" "$blob"
}

if [ "${1:-}" = base ]; then
  root="$2"
  cd "$root" || exit 1
  if ! base=$(timeout 15 "${AGENT_TABS_GH:-gh}" pr view --json baseRefName -q .baseRefName 2>/dev/null) ||
    [ -z "$base" ]; then
    notify "reviewr: no pull request for $root. The target branch stays."
    exit 0
  fi
  if write_pick "$root" "$base"; then
    notify "reviewr: the target branch of $root is $base, from the pull request."
  else
    notify "reviewr: git did not write the target branch $base for $root."
  fi
  exit 0
fi

if [ -z "${HERDR_PANE_ID:-}" ]; then
  notify "reviewr: no pane has focus."
  exit 1
fi

# Return 0 when pane $1 runs herdr-reviewr in the foreground. The label of a pane is
# not a proof.
is_reviewr() {
  "$H" pane process-info --pane "$1" 2>/dev/null | jq -e '
    any(.result.process_info.foreground_processes[];
      ((.argv0 // "") | split("/") | last) == "herdr-reviewr"
      or (((.argv // [])[0] // "") | split("/") | last) == "herdr-reviewr")
  ' >/dev/null
}

if is_reviewr "$HERDR_PANE_ID"; then
  notify "reviewr: the focused pane is a reviewr."
  exit 0
fi
dir=""
file=$(worktree_file "$HERDR_PANE_ID")
[ ! -f "$file" ] || dir=$(head -n 1 "$file")
[ -n "$dir" ] && [ -d "$dir" ] || dir=$(pane_cwd "$HERDR_PANE_ID")
if ! root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
  notify "reviewr: $dir is not in a git repo."
  exit 1
fi

# Find a reviewr pane in the tab of the focused pane with the same worktree. Zoom on it.
# Herdr has no command to focus a pane by ID, and the zoom shows the pane.
panes=$("$H" pane list ${HERDR_WORKSPACE_ID:+--workspace "$HERDR_WORKSPACE_ID"}) || panes='{}'
candidates=$(jq -r --arg me "$HERDR_PANE_ID" --arg root "$root" '
  (.result.panes // []) as $all
  | (first($all[] | select(.pane_id == $me) | .tab_id) // "") as $tab
  | $all[] | select(.tab_id == $tab and .pane_id != $me and .foreground_cwd == $root) | .pane_id
' <<<"$panes") || candidates=""
for pane in $candidates; do
  if is_reviewr "$pane"; then
    "$H" pane zoom "$pane" --on >/dev/null 2>&1 || true
    notify "reviewr: pane $pane already shows $root in this tab."
    # A reviewr sees the turns of a claude in its worktree. For a claude in another
    # worktree, the hooks write the turn base, and the reviewr does not read it again.
    record=$(reviewr_file "$pane")
    if { [ ! -f "$record" ] || [ "$(cat "$record")" != "$(turn_base "$root")" ]; } &&
      [ "$(git -C "$(pane_cwd "$HERDR_PANE_ID")" rev-parse --show-toplevel 2>/dev/null)" != "$root" ]; then
      "$H" notification show "Agent tabs" --body \
        "reviewr shows an older turn. Close it, then press ctrl+b d to see the new turn." >/dev/null 2>&1 || true
    fi
    exit 0
  fi
done

# Write the branch of the reflog as the pick. git writes "branch: Created from X" as the
# first reflog entry of a branch. Skip HEAD, a commit ID and a name that is not a commit.
if branch=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null) &&
  ! git -C "$root" rev-parse --verify --quiet "$pick_ref" >/dev/null; then
  from=$(git -C "$root" reflog show --format=%gs "refs/heads/$branch" -- 2>/dev/null |
    sed -n 's/^branch: Created from //p' | tail -n 1) || from=""
  if [ -n "$from" ] && [ "$from" != HEAD ] && ! [[ "$from" =~ ^[0-9a-f]{7,64}$ ]] &&
    git -C "$root" rev-parse --verify --quiet "$from^{commit}" >/dev/null; then
    from=${from#refs/remotes/origin/}
    from=${from#refs/heads/}
    from=${from#origin/}
    if [ "$from" != "$(default_branch "$root")" ] && write_pick "$root" "$from"; then
      notify "reviewr: the target branch of $root is $from, from the reflog."
    fi
  fi
fi

if ! opened=$("$H" plugin pane open --plugin persiyanov.reviewr --entrypoint pane \
  --placement zoomed --target-pane "$HERDR_PANE_ID" --direction right --cwd "$root" --focus 2>&1); then
  notify "reviewr: Herdr did not open the pane: $opened"
  exit 1
fi
new_pane=$(jq -r '.result.plugin_pane.pane.pane_id // empty' <<<"$opened") || new_pane=""
notify "reviewr: opened pane ${new_pane:-?} for $root."
if [ -n "$new_pane" ]; then
  record=$(reviewr_file "$new_pane")
  if mkdir -p "$(dirname "$record")"; then printf '%s\n' "$(turn_base "$root")" >"$record" || true; fi
fi
start_worker "$root"
