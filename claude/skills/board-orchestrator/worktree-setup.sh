#!/usr/bin/env bash
# worktree-setup.sh DIR LOG -- CMD...: run make worktree-setup in DIR, show its output and
# keep it in LOG, then run CMD in place of this shell. dispatch.sh start puts it before the
# worker claude in a new worktree: the terminal opens at once and shows the setup, and the
# worker starts with a ready worktree. CMD runs also when make fails: the last line of LOG
# gives the exit status, and the worker reads it.
set -uo pipefail
if [ $# -lt 3 ] || [ "$3" != -- ]; then
  printf 'usage: worktree-setup.sh DIR LOG -- CMD...\n' >&2
  exit 2
fi
dir=$1 log=$2
shift 3
# A setup can build or copy a lot: when-free waits until the host has the CPU and the RAM.
free=()
[ ! -x "$HOME/.bin/when-free" ] || free=("$HOME/.bin/when-free")
printf 'worktree-setup: make worktree-setup in %s\n' "$dir" | tee "$log"
# A Ctrl-C stops a hung make, not this script: the worker starts after it. The children
# get the default SIGINT action back.
trap : INT
${free[@]+"${free[@]}"} make -C "$dir" worktree-setup 2>&1 | tee -a "$log"
status=${PIPESTATUS[0]}
# dispatch.sh reads this last line: the setup ended (setup_runs).
printf 'worktree-setup: exit %s\n' "$status" >>"$log"
printf 'worktree-setup: exit %s\n' "$status"
trap - INT
exec "$@"
