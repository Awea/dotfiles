#!/usr/bin/env bash
# PreToolUse hook (Bash) of the board orchestrator on herdr-app. A worker of a board
# must not change the herdr-app window: the user sees only what the orchestrator shows.
# A worker can start other agents (a subagent, or a claude in an hc terminal), for
# example for an independent review: an hc child shows under the worker in the agents
# list. Exit 2 blocks the call.
#
# In a repo with the branch push policy (dispatch.sh policy-set CWD branch), the hook
# also decides each git push of a worker. The policy has no git push rule: an ask rule
# wins over the allow of a hook. The hook asks for the first push of a branch and keeps a
# record of it. A later push to that branch has no question when origin has the branch
# and the branch moved after the question: the user allowed that push. A push to the
# default branch, main or master, a push that the hook cannot read and a PR body edit
# always ask.
set -uo pipefail
# Decide only on hc or Renux, never on HERDR_*: an hc core started from Herdr 0.9.5
# gives its terminals that environment. On hc the role is in the labels. On Renux
# (REX_BLOCK set) the role is in the env of the pane: the hook never reads a record and
# never calls rex, so that it stays fast when Rex is slow.
rex_worker=""
if [ -n "${HC_TERMINAL_ID:-}" ]; then
  :
elif [ -n "${REX_BLOCK:-}" ] && [ -n "${BOARD:-}" ] && [ "${BOARD_ROLE:-}" = worker ]; then
  rex_worker=1
else
  exit 0
fi
# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$(readlink -f "$0")")/../lib.sh"
if [ -z "$rex_worker" ]; then
  labels=$(hc_labels "$HC_TERMINAL_ID") || exit 0
  [ "$(jq -r '.["board.role"] // empty' <<<"$labels")" = worker ] || exit 0
fi

input=$(cat)
command=$(jq -r '.tool_input.command // empty' 2>/dev/null <<<"$input") || exit 0
[ -n "$command" ] || exit 0

block() {
  printf 'board-orchestrator: a board worker cannot %s. Write it in the report: the orchestrator does it.\n' "$1" >&2
  exit 2
}

# decide allow|ask REASON: the permission decision for the call.
decide() {
  jq -cn --arg d "$1" --arg r "board-orchestrator: $2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# rex_check PART: block a rex call that changes the Renux window. The first word is
# the first one after the VAR=value words and the prefix words (do, time, xargs...);
# rex is matched by its basename, without quotes.
rex_check() {
  local -a words
  local j=0 sub w
  read -ra words <<<"$1"
  while [ "$j" -lt "${#words[@]}" ]; do
    w=${words[$j]//[\"\']/}
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then :
    else
      case "$w" in do | then | else | elif | if | while | until | '!' | time | command | env | exec | nohup | xargs | sudo) ;; *) break ;; esac
    fi
    j=$((j + 1))
  done
  w=${words[$j]:-}
  w=${w//[\"\']/}
  [ "${w##*/}" = rex ] || return 0
  sub=${words[$((j + 1))]:-}
  sub=${sub//[\"\']/}
  case "$sub" in
    capture | help | --help | version | keymap) return 0 ;;
    server)
      [ "${words[$((j + 2))]:-}" = status ] && return 0
      sub="server ${words[$((j + 2))]:-}"
      ;;
    api)
      if [ "${words[$((j + 2))]:-}" = call ]; then
        case "${words[$((j + 3))]:-}" in
          session.list | session.list_blocks | session.view | session.describe_block | target.resolve | help.all | session.help) return 0 ;;
        esac
        sub="api call ${words[$((j + 3))]:-}"
      fi
      ;;
  esac
  block "change the Renux window (rex${sub:+ $sub})"
}

# Each part of the command between ; & | and newlines.
push="" edit=""
while IFS= read -r part; do
  read -ra words <<<"$part"
  for ((i = 0; i < ${#words[@]}; i++)); do
    if [ "${words[$i]}" = herdr-app ] && [ "${words[$((i + 1))]:-}" = "do" ]; then
      block "change the herdr-app window (herdr-app do)"
    fi
  done
  if [ -n "$rex_worker" ]; then
    while IFS= read -r sp; do rex_check "$sp"; done < <(tr '`(){}' '\n' <<<"$part")
  fi
  # A git push, also after git options. A gh pr edit.
  [[ ! "$part" =~ (^|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$) ]] || push=1
  [[ ! "$part" =~ (^|[[:space:]])gh[[:space:]]+pr[[:space:]]+edit([[:space:]]|$) ]] || edit=1
done < <(tr ';&|' '\n' <<<"$command")
[ -n "$push$edit" ] || exit 0

# The folder of the call: the cwd of the hook, then a leading "cd DIR &&", then git -C.
dir=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$dir" ] || dir=$PWD
# Each word has only safe marks: no other command (; & | < > $ ` ( ) and newline), no
# quote, no glob, no negative refspec (^).
safe='^[A-Za-z0-9_./:@+=,-]+$'
simple=1
rest=$command
if [[ "$rest" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]\;\&\|]+)[[:space:]]*\&\&[[:space:]]*(.*)$ ]]; then
  target=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
  if [[ "$target" =~ $safe ]]; then
    [[ "$target" == /* ]] || target="$dir/$target"
    dir=$target
  else
    simple=""
  fi
fi
read -ra words <<<"$rest"
for w in ${words[@]+"${words[@]}"}; do
  [[ "$w" =~ $safe ]] || simple=""
done
[[ "$rest" != *$'\n'* ]] || simple=""
i=1
if [ -n "$simple" ] && [ "${words[0]:-}" = git ]; then
  while [ "${words[$i]:-}" = -C ]; do
    target=${words[$((i + 1))]:-}
    [[ "$target" == /* ]] || target="$dir/$target"
    dir=$target
    i=$((i + 2))
  done
  [ "${words[$i]:-}" = push ] || simple=""
else
  simple=""
fi

# The policy of the folder of the call, or of a parent folder up to the top of the repo:
# the card folder can be a sub-folder.
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
policy=missing
at=$(cd -- "$dir" 2>/dev/null && pwd -P) || at=$top
top=$(cd -- "$top" && pwd -P)
while :; do
  policy=$( (push_policy "$at") 2>/dev/null) || exit 0
  if [ "$policy" != missing ] || [ "$at" = "$top" ] || [ "$at" = / ]; then break; fi
  at=$(dirname "$at")
done
[ "$policy" = branch ] || exit 0

[ -z "$edit" ] || decide ask "the branch push policy always asks for a PR body edit (gh pr edit)."
[ -n "$simple" ] || decide ask "the branch push policy allows only one git push command, with no other command, quote or variable. Ask the user."

git=(git -C "$top")
current=$("${git[@]}" symbolic-ref -q --short HEAD 2>/dev/null) || current=""

# The options and the refspecs of the push. --force-with-lease stays free on a branch
# that the user allowed: a rebase onto the default branch needs it.
remote="" refspecs=()
for ((i = i + 1; i < ${#words[@]}; i++)); do
  w=${words[$i]}
  case "$w" in
    -u | --set-upstream | -q | --quiet | -v | --verbose | --progress | --no-verify | --porcelain | \
      -n | --dry-run | --force-with-lease | --force-with-lease=* | --force-if-includes) ;;
    -*) decide ask "the branch push policy asks for a push with the option $w." ;;
    *)
      if [ -z "$remote" ]; then remote=$w; else refspecs+=("$w"); fi
      ;;
  esac
done

# A push with no remote goes to the push remote of the branch.
if [ -z "$remote" ]; then
  remote=$("${git[@]}" config "branch.$current.pushRemote" 2>/dev/null) ||
    remote=$("${git[@]}" config remote.pushDefault 2>/dev/null) ||
    remote=$("${git[@]}" config "branch.$current.remote" 2>/dev/null) || remote=origin
fi
[ "$remote" = origin ] || decide ask "the branch push policy asks for a push to the remote $remote."
# A setting that changes where or what the push goes to.
if "${git[@]}" config --get-all remote.origin.push >/dev/null 2>&1 ||
  "${git[@]}" config --get-all remote.origin.pushurl >/dev/null 2>&1 ||
  [ "$("${git[@]}" config --type=bool remote.origin.mirror 2>/dev/null)" = true ] ||
  "${git[@]}" config --get-regexp '^url\..*\.pushinsteadof$' >/dev/null 2>&1; then
  decide ask "the branch push policy asks for a push with a push setting of origin (push, pushurl, mirror or pushInsteadOf)."
fi
# A submodule push goes to the remote of the submodule.
case "$("${git[@]}" config push.recurseSubmodules 2>/dev/null)" in
  on-demand | only) decide ask "the branch push policy asks for a push with push.recurseSubmodules." ;;
esac
if [ "$("${git[@]}" config --type=bool submodule.recurse 2>/dev/null)" = true ]; then
  decide ask "the branch push policy asks for a push with submodule.recurse."
fi

# branch_of REF: the local branch of REF (HEAD, @ or a branch), else exit 1.
branch_of() {
  local full
  full=$("${git[@]}" rev-parse -q --verify --symbolic-full-name "$1" 2>/dev/null) || return 1
  [[ "$full" == refs/heads/?* ]] || return 1
  printf '%s\n' "${full#refs/heads/}"
}

# The target branches. A push with no refspec pushes the current branch, to its
# upstream when it has one.
targets=()
if [ "${#refspecs[@]}" -eq 0 ]; then
  case "$("${git[@]}" config push.default 2>/dev/null || echo simple)" in
    simple | current | upstream | tracking) ;;
    *) decide ask "the branch push policy asks for a push with the push.default setting $("${git[@]}" config push.default)." ;;
  esac
  [ -n "$current" ] || decide ask "the branch push policy asks for a push from a detached HEAD."
  targets+=("$current")
  upstream=$("${git[@]}" config "branch.$current.merge" 2>/dev/null) || upstream=""
  [ -z "$upstream" ] || [ "${upstream#refs/heads/}" = "$current" ] || targets+=("${upstream#refs/heads/}")
fi
for spec in ${refspecs[@]+"${refspecs[@]}"}; do
  case "$spec" in
    +*) decide ask "the branch push policy asks for a forced push ($spec)." ;;
    :*) decide ask "the branch push policy asks for a branch delete ($spec)." ;;
    *:*) src=${spec%%:*} dst=${spec#*:} ;;
    *) src=$spec dst="" ;;
  esac
  # The source must be a local branch: a tag or a commit makes git guess the target.
  branch=$(branch_of "$src") || decide ask "the branch push policy asks for a push of $src, which is not a local branch."
  if [ -z "$dst" ] || [ "$dst" = HEAD ] || [ "$dst" = @ ]; then
    dst=$branch
  elif [[ "$dst" == refs/heads/?* ]]; then
    dst=${dst#refs/heads/}
  fi
  # A short name such as heads/master or tags/v1 also matches a ref of origin.
  case "$dst" in
    refs/* | heads/* | tags/* | remotes/* | *[~:^@]*) decide ask "the branch push policy asks for a push to $dst." ;;
  esac
  targets+=("$dst")
done

# The state of origin: its default branch and the commit of each target branch. A worker
# can change its local origin refs, so the hook reads origin itself.
# The hook has 10 s: a watchdog stops the read after 5 s (macOS has no timeout). The ssh
# command keeps core.sshCommand, as git does, and asks for no password.
ssh_cmd=${GIT_SSH_COMMAND:-$("${git[@]}" config core.sshCommand 2>/dev/null || echo ssh)}
out=$(mktemp "${TMPDIR:-/tmp}/board-push.XXXXXX")
(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh_cmd -o BatchMode=yes -o ConnectTimeout=3" \
  exec "${git[@]}" ls-remote --symref origin HEAD "${targets[@]/#/refs/heads/}" >"$out" 2>/dev/null </dev/null 3>&-) &
pid=$!
for ((n = 0; n < 50; n++)); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null
  rm -f "$out"
  decide ask "the branch push policy asks: the hook could not read origin in 5 s."
fi
if ! wait "$pid"; then
  rm -f "$out"
  decide ask "the branch push policy asks: the hook could not read origin."
fi
remote_refs=$(<"$out")
rm -f "$out"
default=$(awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }' <<<"$remote_refs")
local_default=$("${git[@]}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || local_default=""
protected=" main master ${default} ${local_default#origin/} "
for b in "${targets[@]}"; do
  [[ "$protected" != *" $b "* ]] || decide ask "the branch push policy always asks for a push to the default branch $b."
done

# The record: one line "SESSION<tab>REPO<tab>BRANCH<tab>STATE" for each branch that the
# hook asked for. STATE is ok, or ask:<the origin commit of the branch at the question>.
# The branch is ok when origin has it at another commit: the user allowed the push.
session=$(jq -r '.session_id // empty' <<<"$input")
[ -n "$session" ] || decide ask "the branch push policy asks: the call has no session ID."
repo=$(cd -- "$top" && cd -- "$(git rev-parse --git-common-dir)" && pwd -P) || repo=$top
record="$(state_dir)/pushes"
touch "$record"
asked=()
for b in "${targets[@]}"; do
  now=$(awk -v r="refs/heads/$b" '$2 == r { print $1; exit }' <<<"$remote_refs")
  now=${now:-none}
  state=$(awk -F '\t' -v s="$session" -v r="$repo" -v b="$b" '$1 == s && $2 == r && $3 == b { print $4; exit }' "$record")
  case "$state" in
    ok) ;;
    ask:*)
      if [ "$now" != none ] && [ "$now" != "${state#ask:}" ]; then
        tmp=$(mktemp "$record.XXXXXX")
        awk -F '\t' -v OFS='\t' -v s="$session" -v r="$repo" -v b="$b" \
          '$1 == s && $2 == r && $3 == b { $4 = "ok" } { print }' "$record" >"$tmp" && mv "$tmp" "$record"
      else
        asked+=("$b")
      fi
      ;;
    *)
      printf '%s\t%s\t%s\task:%s\n' "$session" "$repo" "$b" "$now" >>"$record"
      asked+=("$b")
      ;;
  esac
done
[ "${#asked[@]}" -eq 0 ] ||
  decide ask "the branch push policy asks for the first push of the branch ${asked[*]}. Later pushes to it have no question."
decide allow "the user allowed the first push of the branch ${targets[*]}."
