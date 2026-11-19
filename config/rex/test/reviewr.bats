#!/usr/bin/env bats
# reviewr-target, reviewr-pick and reviewr.sh: ctrl+b d in Renux opens reviewr on the
# worktree and base that an agent set with reviewr-target.

load helper

setup() {
  hc_setup
  REC="$XDG_STATE_HOME/rex/reviewr"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
  mkdir -p "$REPO/sub"
  WT="$BATS_TEST_TMPDIR/wt"
  git init -q "$WT"
  mkdir -p "$WT/deep"
}

@test "reviewr-target writes the record of REX_BLOCK" {
  REX_BLOCK=blk1 run "$BIN/reviewr-target" "$WT" abc123
  [ "$status" -eq 0 ]
  [ "$(jq -r .dir "$REC/blk1.json")" = "$(cd "$WT" && pwd -P)" ]
  [ "$(jq -r .base "$REC/blk1.json")" = abc123 ]
}

@test "reviewr-target outside Renux exits 2 and writes nothing" {
  run "$BIN/reviewr-target" "$WT" abc123
  [ "$status" -eq 2 ]
  [[ $output == *"reviewr-target: run this in a Renux pane (REX_BLOCK is not set)."* ]]
  [ ! -e "$REC" ]
}

@test "reviewr-target with no BASE writes a null base" {
  REX_BLOCK=blk1 run "$BIN/reviewr-target" "$WT" ""
  [ "$status" -eq 0 ]
  [ "$(jq -r '.base' "$REC/blk1.json")" = null ]
  [ "$(jq -r '.base == null' "$REC/blk1.json")" = true ]
}

@test "reviewr-target exits 2 when DIR is not a folder" {
  REX_BLOCK=blk1 run "$BIN/reviewr-target" "$BATS_TEST_TMPDIR/none" abc
  [ "$status" -eq 2 ]
  [ ! -e "$REC/blk1.json" ]
}

@test "reviewr-pick uses the record" {
  REX_BLOCK=blk1 "$BIN/reviewr-target" "$WT/deep" abc123
  run "$BIN/reviewr-pick" blk1 "$REPO/sub"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$WT" && pwd -P)" ]
  [ "${lines[1]}" = abc123 ]
}

@test "reviewr-pick falls back to the pane folder when the worktree is gone" {
  REX_BLOCK=blk1 "$BIN/reviewr-target" "$WT/deep" abc123
  rm -rf "$WT"
  run "$BIN/reviewr-pick" blk1 "$REPO/sub"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$REPO" && pwd -P)" ]
  [ -z "${lines[1]}" ]
}

@test "reviewr-pick with no record gives the git root of the pane folder and no base" {
  run "$BIN/reviewr-pick" blk9 "$REPO/sub"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$REPO" && pwd -P)" ]
  [ -z "${lines[1]}" ]
  [ "$("$BIN/reviewr-pick" blk9 "$REPO/sub" | wc -l | tr -d " ")" -eq 2 ]
}

@test "reviewr-pick gives the pane folder when it is not in a repo" {
  mkdir "$BATS_TEST_TMPDIR/plain"
  run "$BIN/reviewr-pick" blk9 "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$BATS_TEST_TMPDIR/plain" ]
}

fake_reviewr() {
  cat >"$BATS_TEST_TMPDIR/fake-reviewr" <<'SH'
#!/usr/bin/env bash
echo "args=$*"
echo "config=$HERDR_PLUGIN_CONFIG_DIR"
SH
  chmod +x "$BATS_TEST_TMPDIR/fake-reviewr"
  export REVIEWR_BIN="$BATS_TEST_TMPDIR/fake-reviewr"
}

@test "reviewr.sh with BASE uses the branch config and --base" {
  fake_reviewr
  run "$BIN/reviewr.sh" "$WT" abc123
  [ "$status" -eq 0 ]
  [[ $output == *"args=--base abc123 $WT"* ]]
  [[ $output == *"config="*"/herdr-app/reviewr-branch"* ]]
}

@test "reviewr.sh without BASE is unchanged" {
  fake_reviewr
  run "$BIN/reviewr.sh" "$WT"
  [ "$status" -eq 0 ]
  [[ $output == *"args=$WT"* ]]
  [[ $output != *"--base"* ]]
  [[ $output == *"/herdr-app/reviewr" ]] || [[ $output == *"/herdr-app/reviewr"$'\n'* ]]
}

@test "reviewr-pick finds jq in ~/.local/bin when the server PATH lacks it" {
  local nojq="$BATS_TEST_TMPDIR/nojq" real_jq
  real_jq=$(command -v jq)
  mkdir -p "$nojq" "$HOME/.local/bin"
  for t in env bash git; do ln -s "$(command -v "$t")" "$nojq/$t"; done
  printf '#!/bin/sh\ntouch "%s/jq-used"\nexec %s "$@"\n' "$BATS_TEST_TMPDIR" "$real_jq" >"$HOME/.local/bin/jq"
  chmod +x "$HOME/.local/bin/jq"
  REX_BLOCK=blk1 "$BIN/reviewr-target" "$WT" abc123
  rm -f "$BATS_TEST_TMPDIR/jq-used"
  PATH="$nojq" run "$BIN/reviewr-pick" blk1 "$REPO/sub"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$WT" && pwd -P)" ]
  [ "${lines[1]}" = abc123 ]
  [ -e "$BATS_TEST_TMPDIR/jq-used" ]
}

@test "a path and a base with a space go from reviewr-target to reviewr.sh" {
  fake_reviewr
  local sp="$BATS_TEST_TMPDIR/my repo"
  git init -q "$sp"
  REX_BLOCK=blk1 "$BIN/reviewr-target" "$sp" "my base"
  local picked root base
  picked=$("$BIN/reviewr-pick" blk1 "$REPO")
  root=$(printf '%s\n' "$picked" | sed -n 1p)
  base=$(printf '%s\n' "$picked" | sed -n 2p)
  [ "$base" = "my base" ]
  run "$BIN/reviewr.sh" "$root" "$base"
  [ "$status" -eq 0 ]
  [[ $output == *"args=--base my base $(cd "$sp" && pwd -P)"* ]]
}
