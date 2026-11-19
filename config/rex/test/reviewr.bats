#!/usr/bin/env bats
# reviewr-target, reviewr-pick and reviewr.sh: ctrl+b d in Renux opens reviewr on the
# worktree and base that an agent set with reviewr-target.

load helper

setup() {
  base_setup
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

# commit REPO MESSAGE: an empty commit in REPO.
commit() {
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "$2"
}

# clone_with_work: ORIGIN, a bare repo with one master commit, and CL, its clone, with one
# more master commit that is not pushed. Sets FORK, the master commit before that one.
clone_with_work() {
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  CL="$BATS_TEST_TMPDIR/clone"
  git init -q --bare -b master "$ORIGIN"
  git clone -q "$ORIGIN" "$CL" 2>/dev/null
  git -C "$CL" switch -q -c master 2>/dev/null || true
  commit "$CL" base
  git -C "$CL" push -q -u origin master 2>/dev/null
  git -C "$CL" remote set-head origin master
  commit "$CL" unpushed
  FORK=$(git -C "$CL" rev-parse --short HEAD)
}

@test "reviewr-pick with no record on a branch gives the commit where it left local master" {
  clone_with_work
  git -C "$CL" switch -q -c work
  commit "$CL" work
  commit "$CL" more
  run "$BIN/reviewr-pick" blk9 "$CL"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$CL" && pwd -P)" ]
  [ "${lines[1]}" = "$FORK" ]
}

@test "reviewr-pick with no record on master gives its upstream" {
  clone_with_work
  run "$BIN/reviewr-pick" blk9 "$CL"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(git -C "$CL" rev-parse --short origin/master)" ]
}

@test "reviewr-pick with no record finds the default branch from origin/HEAD" {
  clone_with_work
  git -C "$CL" branch -q -m master main
  git -C "$CL" push -q origin main 2>/dev/null
  git -C "$CL" remote set-head origin main
  # A local master on an older commit: only origin/HEAD gives main.
  git -C "$CL" branch -q master main~1
  git -C "$CL" switch -q -c work
  commit "$CL" work
  run "$BIN/reviewr-pick" blk9 "$CL"
  [ "${lines[1]}" = "$(git -C "$CL" rev-parse --short main)" ]
}

@test "reviewr-pick with no record skips an origin/HEAD that names a gone branch" {
  clone_with_work
  git -C "$CL" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
  git -C "$CL" switch -q -c work
  commit "$CL" work
  run "$BIN/reviewr-pick" blk9 "$CL"
  [ "${lines[1]}" = "$FORK" ]
}

@test "reviewr-pick with no record takes the newest fork of local and origin master" {
  clone_with_work
  # origin/master moves on, local master stays behind, the branch starts on origin/master.
  git -C "$CL" push -q origin master 2>/dev/null
  git -C "$CL" switch -q -c work origin/master
  git -C "$CL" branch -q -f master master~1
  commit "$CL" work
  run "$BIN/reviewr-pick" blk9 "$CL"
  [ "${lines[1]}" = "$(git -C "$CL" rev-parse --short origin/master)" ]
}

@test "reviewr-pick with no record on an orphan branch gives no base and exits 0" {
  clone_with_work
  git -C "$CL" switch -q --orphan lone
  commit "$CL" lone
  run "$BIN/reviewr-pick" blk9 "$CL"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(cd "$CL" && pwd -P)" ]
  [ -z "${lines[1]}" ]
}

@test "reviewr-pick with no record on master with no upstream gives no base" {
  git init -q -b master "$BATS_TEST_TMPDIR/solo"
  commit "$BATS_TEST_TMPDIR/solo" base
  run "$BIN/reviewr-pick" blk9 "$BATS_TEST_TMPDIR/solo"
  [ "$status" -eq 0 ]
  [ -z "${lines[1]}" ]
}

@test "reviewr-pick gives a base for the folder of a record with no base" {
  clone_with_work
  git -C "$CL" switch -q -c work
  commit "$CL" work
  REX_BLOCK=blk1 "$BIN/reviewr-target" "$CL" ""
  run "$BIN/reviewr-pick" blk1 "$REPO/sub"
  [ "${lines[0]}" = "$(cd "$CL" && pwd -P)" ]
  [ "${lines[1]}" = "$FORK" ]
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

@test "the reviewr config opens the branch scope" {
  grep -qx 'default_scope = "branch"' "$BIN/../reviewr/config.toml"
  [ ! -e "$BIN/../reviewr-branch" ]
}

@test "reviewr.sh with BASE uses the reviewr config and --base" {
  fake_reviewr
  run "$BIN/reviewr.sh" "$WT" abc123
  [ "$status" -eq 0 ]
  [[ $output == *"args=--base abc123 $WT"* ]]
  [[ $output == *"/config/rex/reviewr" ]] || [[ $output == *"/config/rex/reviewr"$'\n'* ]]
}

@test "reviewr.sh without BASE has no --base" {
  fake_reviewr
  run "$BIN/reviewr.sh" "$WT"
  [ "$status" -eq 0 ]
  [[ $output == *"args=$WT"* ]]
  [[ $output != *"--base"* ]]
  [[ $output == *"/config/rex/reviewr" ]] || [[ $output == *"/config/rex/reviewr"$'\n'* ]]
}

@test "reviewr.sh does not run a reviewr from the old Herdr plugin folder" {
  plugin="$HOME/.config/herdr/plugins/github/persiyanov.reviewr-x/bin"
  mkdir -p "$plugin"
  printf '#!/usr/bin/env bash\necho plugin-reviewr\n' >"$plugin/herdr-reviewr"
  chmod +x "$plugin/herdr-reviewr"
  PATH=/usr/bin:/bin SHELL=/bin/true run "$BIN/reviewr.sh" "$WT" </dev/null
  [[ $output == *"herdr-reviewr is not installed"* ]]
  [[ $output != *plugin-reviewr* ]]
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

@test "herdr-shim gives the reviewr config of config/rex" {
  run "$BIN/herdr-shim" plugin config-dir
  [ "$status" -eq 0 ]
  [[ $output == */config/rex/reviewr ]]
}
