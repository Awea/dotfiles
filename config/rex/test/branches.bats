#!/usr/bin/env bats
# branches-repos and branches-pick.sh (the branch view of ctrl+b shift+l), and branches-open
# (a branch view tab for an agent).

load helper

setup() {
  base_setup
  A="$BATS_TEST_TMPDIR/alpha"
  B="$BATS_TEST_TMPDIR/beta"
  git init -q "$A"
  git init -q "$B"
  mkdir -p "$A/sub" "$BATS_TEST_TMPDIR/plain"
  export _Z_DATA="$HOME/.z"
  : >"$_Z_DATA"
}

# z DIR...: the z list, the first DIR most frecent.
z() {
  local rank=100 dir
  for dir in "$@"; do
    printf '%s|%s|%s\n' "$dir" "$rank" "$(date +%s)" >>"$_Z_DATA"
    rank=$((rank - 10))
  done
}

@test "branches-repos lists the repo of DIR first" {
  z "$B" "$A"
  run "$BIN/branches-repos" "$A/sub"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$A" ]
  [ "${lines[1]}" = "$B" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "branches-repos gives a repo once for a subfolder" {
  z "$A/sub" "$A"
  run "$BIN/branches-repos" "$HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "$A" ]
}

@test "branches-repos skips a folder that is not a repo" {
  z "$BATS_TEST_TMPDIR/plain" "$B"
  run "$BIN/branches-repos" "$HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "$B" ]
}

@test "branches-repos with DIR outside a repo lists the z repos" {
  z "$B" "$A"
  run "$BIN/branches-repos" "$HOME"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$B" ]
  [ "${lines[1]}" = "$A" ]
}

# fake_bin NAME BODY: a fake program in ~/.local/bin, which the scripts put first in PATH.
fake_bin() {
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$HOME/.local/bin/$1"
  chmod +x "$HOME/.local/bin/$1"
}

# fake_fzf PICK: a fake fzf that logs "fzf". The first call prints line PICK of its input
# (0: Esc). Each later call is Esc.
fake_fzf() {
  fake_bin fzf "n=\$(cat \"\$FAKE_DIR/fzf-n\" 2>/dev/null || echo 0); echo \$((n + 1)) >\"\$FAKE_DIR/fzf-n\"
echo fzf >>\"\$FAKE_LOG\"
input=\$(cat)
[ \"\$n\" = 0 ] && [ $1 != 0 ] || exit 130
sed -n '$1p' <<<\"\$input\""
}

@test "branches-pick.sh opens serie on the repo of DIR at once" {
  z "$B"
  fake_fzf 0
  fake_bin serie 'printf "serie %s\n" "$*" >>"$FAKE_LOG"'
  run "$BIN/branches-pick.sh" "$A/sub" session:s block:b client:c
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_LOG")" = "serie -p kitty -C $A"$'\n'"fzf" ]
}

@test "branches-pick.sh shows the list when serie quits, and opens the picked repo" {
  H="$HOME/work/home-repo"
  git init -q "$H"
  z "$H"
  fake_fzf 2
  fake_bin serie 'printf "serie %s\n" "$*" >>"$FAKE_LOG"'
  run "$BIN/branches-pick.sh" "$A" session:s block:b client:c
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_LOG")" = "serie -p kitty -C $A"$'\n'"fzf"$'\n'"serie -p kitty -C $H"$'\n'"fzf" ]
}

@test "branches-pick.sh outside a repo shows the list first" {
  z "$B"
  fake_fzf 0
  fake_bin serie 'printf "serie %s\n" "$*" >>"$FAKE_LOG"'
  run "$BIN/branches-pick.sh" "$HOME" session:s block:b client:c
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_LOG")" = "fzf" ]
}

# in_space: the caller is a pane of the fake Rex session session:fake-1.
in_space() {
  export REX_BIN="$FAKES/fake-rex"
  mkdir -p "$FAKE_DIR/rex"
  "$REX_BIN" new main --json >/dev/null
  export REX_SESSION=session:fake-1 REX_BLOCK=block:me
  fake_bin serie :
}

# rex_run_args [N]: the arguments of the Nth rex run call, in the array RUN_ARGS.
rex_run_args() {
  mapfile -d '' RUN_ARGS <"$FAKE_DIR/rex/rex-run-${1:-1}.args"
}

@test "branches-open opens a tab on the git root" {
  in_space
  run "$BIN/branches-open" "$A/sub"
  [ "$status" -eq 0 ]
  [ "$output" = 'branches-open: the tab "branches alpha" is open in this space.' ]
  rex_run_args
  [ "$(arg_after -s)" = session:fake-1 ]
  [ "$(arg_after --label)" = "branches alpha" ]
  [ "$(arg_after --cwd)" = "$A" ]
  [ "$(arg_after --)" = "$HOME/.local/bin/serie" ]
  [ "$(arg_after -p)" = kitty ]
  has_arg --focus=false
  ! has_arg --keep-open
}

# tab_cwd N DIR: the Nth fake block runs a live program in DIR.
tab_cwd() {
  jq -n --arg d "$2" '{child: {cwd: $d}, last_exit: null}' \
    >"$FAKE_DIR/rex/process-$(printf 'block:00000000-0000-0000-0000-%012d' "$1").json"
}

@test "branches-open does not open a second tab" {
  in_space
  "$BIN/branches-open" "$A"
  tab_cwd 2 "$A"
  run "$BIN/branches-open" "$A/sub"
  [ "$status" -eq 0 ]
  [ "$output" = 'branches-open: the tab "branches alpha" is open in this space.' ]
  [ "$(calls '^rex run ' | wc -l)" -eq 1 ]
}

@test "branches-open opens a tab for a second repo of the same name" {
  in_space
  X="$BATS_TEST_TMPDIR/x/api"
  Y="$BATS_TEST_TMPDIR/y/api"
  git init -q "$X"
  git init -q "$Y"
  "$BIN/branches-open" "$X"
  tab_cwd 2 "$X"
  run "$BIN/branches-open" "$Y"
  [ "$status" -eq 0 ]
  [ "$(calls '^rex run ' | wc -l)" -eq 2 ]
  rex_run_args 2
  [ "$(arg_after --cwd)" = "$Y" ]
}

@test "branches-open outside Renux exits 2" {
  export REX_BIN="$FAKES/fake-rex"
  run "$BIN/branches-open" "$A"
  [ "$status" -eq 2 ]
  [ "$output" = 'branches-open: run this in a Renux pane (REX_SESSION is not set).' ]
  [ -z "$(calls '^rex run ')" ]
}

@test "branches-open on a folder that is not a repo exits 2" {
  in_space
  run "$BIN/branches-open" "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 2 ]
  [ -z "$(calls '^rex run ')" ]
}

@test "branches-open exits 1 when rex fails" {
  in_space
  export FAKE_REX_FAIL=1
  run "$BIN/branches-open" "$A"
  [ "$status" -eq 1 ]
}

@test "branches-open exits 1 when serie is not installed" {
  # branches-open looks in these folders too: the Brewfile puts serie there on macOS.
  [ ! -x /opt/homebrew/bin/serie ] && [ ! -x /usr/local/bin/serie ] || skip "serie is installed system-wide"
  in_space
  rm "$HOME/.local/bin/serie"
  run env PATH=/usr/bin:/bin "$BIN/branches-open" "$A"
  [ "$status" -eq 1 ]
  [ "$output" = "branches-open: serie is not installed." ]
  [ -z "$(calls '^rex run ')" ]
}
