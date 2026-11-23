#!/usr/bin/env bats
# Tests of mem-top. A fake process table and fake memory numbers come from files.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  MT="$BATS_TEST_DIRNAME/../mem-top"
  T=$BATS_TEST_TMPDIR
  export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
  git config --global user.name test
  git config --global user.email test@example.com
  export MEM_TOP_WORKTREES="$T/wts"
  printf '#!/usr/bin/env bash\ncat %q\n' "$T/ps" >"$T/ps.sh"
  printf '#!/usr/bin/env bash\ncat %q\n' "$T/mem" >"$T/mem.sh"
  chmod +x "$T/ps.sh" "$T/mem.sh"
  export MEM_TOP_PS="$T/ps.sh" MEM_TOP_MEM="$T/mem.sh"
  unset MEM_TOP_SWAP_PCT MEM_TOP_MIN_MB
  : >"$T/ps"
  mem 32768 8000 20000 1000
}

# mem TOTAL AVAIL SWAP_TOTAL SWAP_USED: the fake memory numbers, in MB.
mem() { printf '%s %s %s %s\n' "$@" >"$T/mem"; }

# proc PID TTY RSS_KB SWAP_KB CWD NAME: a row of the fake process table.
proc() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$T/ps"; }

# worktree REPO CARD: a git worktree of the repo REPO (made once) in the worktrees folder.
# Prints its path.
worktree() {
  local main="$T/$1" wt="$MEM_TOP_WORKTREES/$1/$2"
  if [ ! -d "$main" ]; then
    git init -q "$main"
    git -C "$main" commit -q --allow-empty -m first
  fi
  git -C "$main" worktree add -q -b "$2" "$wt"
  printf '%s\n' "$wt"
}

@test "--orphans lists a process with no terminal in a worktree with no worker" {
  wt=$(worktree shop card-a)
  mkdir -p "$wt/db/pgdata"
  proc 101 '?' 30720 10240 "$wt/db/pgdata" postgres
  run "$MT" --orphans
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\t101\t40\tpostgres' "$wt")" ]
}

@test "--orphans reads a worktrees folder behind a link" {
  wt=$(worktree shop card-a)
  ln -s "$MEM_TOP_WORKTREES" "$T/link"
  proc 101 '?' 30720 10240 "$wt" postgres
  MEM_TOP_WORKTREES="$T/link" run "$MT" --orphans
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\t101\t40\tpostgres' "$wt")" ]
}

@test "--orphans skips a worktree where a process has a terminal" {
  wt=$(worktree shop card-a)
  proc 101 '?' 30720 0 "$wt" postgres
  proc 102 pts/3 2048 0 "$wt" zsh
  run "$MT" --orphans
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--orphans skips a worktree when claude runs in a worktree of the same card in another repo" {
  wt=$(worktree shop card-a)
  other=$(worktree board card-a)
  proc 101 '?' 30720 0 "$wt" postgres
  proc 200 pts/4 300000 0 "$other" claude
  run "$MT" --orphans
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--orphans skips a process outside the worktrees folder or with a deleted folder" {
  wt=$(worktree shop card-a)
  proc 101 '?' 30720 0 "$T/shop" postgres
  proc 102 '?' 30720 0 "$wt/gone (deleted)" sleep
  run "$MT" --orphans
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--check is quiet and exits 0 when the swap and the RAM are fine" {
  run "$MT" --check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--check warns when the swap is at 80 % or more" {
  mem 32768 8000 20000 17000
  run "$MT" --check
  [ "$status" -eq 1 ]
  [ "$output" = "RAM: swap 16.6/19.5 GiB (85 %), 7.8 GiB available." ]
}

@test "--check warns when the available RAM is under 2048 MB" {
  mem 32768 1000 20000 1000
  run "$MT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"1.0 GiB available"* ]]
}

@test "--check takes the limits from the env, and a host with no swap checks only the RAM" {
  mem 32768 3000 0 0
  run "$MT" --check
  [ "$status" -eq 0 ]
  MEM_TOP_MIN_MB=4096 run "$MT" --check
  [ "$status" -eq 1 ]
}

@test "the report shows the RAM, the top programs by RSS and swap, and the orphans" {
  wt=$(worktree shop card-a)
  proc 1 pts/1 1048576 2097152 "$T" firefox
  proc 2 pts/1 1048576 0 "$T" firefox
  proc 3 pts/2 512000 0 "$T" zed
  proc 4 '?' 30720 0 "$wt" postgres
  run "$MT" -n 2
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "RAM: 24.2/32.0 GiB used, 7.8 GiB available. Swap: 1.0/19.5 GiB (5 %)." ]]
  [[ "${lines[2]}" =~ ^\ +4096\ +2048\ +2048\ +2\ +firefox$ ]]
  [[ "${lines[3]}" =~ ^\ +500\ +500\ +0\ +1\ +zed$ ]]
  [ "${lines[4]}" = "Dev servers with no worker:" ]
  [[ "$output" == *"shop/card-a: postgres (pid 4, 30 MB)"* ]]
}

@test "the report says when no dev server runs with no worker" {
  run "$MT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev servers with no worker: none."* ]]
}

@test "the report cuts a long top list and still shows the orphans" {
  for i in $(seq 3000); do printf '%s\tpts/1\t%s\t0\t/\tprog%s\n' "$i" "$((i * 1024))" "$i"; done >"$T/ps"
  run "$MT" -n 1
  [ "$status" -eq 0 ]
  [[ "${lines[2]}" =~ prog3000$ ]]
  [ "${lines[3]}" = "Dev servers with no worker: none." ]
}
