#!/usr/bin/env bats
# Tests of multica/agent-init (the setup inside the multica-agent session), with a fake
# multica, a fake id and a fake ls-remote. git config writes a test global file.
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  INIT="$BATS_TEST_DIRNAME/../../multica/agent-init"
  export HOME="$BATS_TEST_TMPDIR/home"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  mkdir -p "$HOME/.claude"
  echo '{}' >"$HOME/.claude/.credentials.json"
  LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$LOG"
  F="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$F"
  # The fake multica: as the real one, auth status exits 0 even with no login; workspace
  # list fails until the file logged-in is there; login makes it.
  cat >"$F/multica" <<EOF
#!/usr/bin/env bash
printf 'multica %s\n' "\$*" >>"$LOG"
case "\$1 \$2" in
  "auth status") echo "Not authenticated." ;;
  "workspace list") [ -f "$BATS_TEST_TMPDIR/logged-in" ] ;;
  "login "*) touch "$BATS_TEST_TMPDIR/logged-in" ;;
esac
EOF
  printf '#!/usr/bin/env bash\necho multica-agent\n' >"$F/id"
  # ls-remote works for the owners listed in ok.txt.
  cat >"$F/ls-remote" <<EOF
#!/usr/bin/env bash
printf 'ls-remote %s\n' "\$*" >>"$LOG"
owner=\${1#https://github.com/}; owner=\${owner%%/*}
grep -qx "\$owner" "$BATS_TEST_TMPDIR/ok.txt" 2>/dev/null && echo "abc123	HEAD"
EOF
  chmod +x "$F"/*
  export MULTICA_BIN="$F/multica" ID_BIN="$F/id" LS_REMOTE_BIN="$F/ls-remote"
}

@test "init runs only as multica-agent" {
  printf '#!/usr/bin/env bash\necho awea\n' >"$BATS_TEST_TMPDIR/fake/id"
  run "$INIT" </dev/null
  [ "$status" -eq 2 ]
  [ ! -s "$LOG" ]
}

@test "init logs in to multica, switches to perso and saves one hidden token per owner" {
  printf 'Awea\nwearemd\n' >"$BATS_TEST_TMPDIR/ok.txt"
  run "$INIT" < <(printf 'tokenA\ntokenW\n')
  [ "$status" -eq 0 ]
  grep -qxF 'multica login' "$LOG"
  grep -qxF 'multica workspace switch perso' "$LOG"
  [ "$(git config --global url.https://x-access-token:tokenA@github.com/Awea/.insteadOf)" = https://github.com/Awea/ ]
  [ "$(git config --global url.https://x-access-token:tokenW@github.com/wearemd/.insteadOf)" = https://github.com/wearemd/ ]
  grep -qxF 'ls-remote https://github.com/Awea/game-guesser HEAD' "$LOG"
  grep -qxF 'ls-remote https://github.com/wearemd/server-playbooks HEAD' "$LOG"
  [[ "$output" != *tokenA* ]]
}

@test "a second init asks for nothing and logs in no more" {
  printf 'Awea\nwearemd\n' >"$BATS_TEST_TMPDIR/ok.txt"
  "$INIT" < <(printf 'tokenA\ntokenW\n') >/dev/null
  : >"$LOG"
  run "$INIT" </dev/null
  [ "$status" -eq 0 ]
  run grep -c 'multica login' "$LOG"
  [ "$output" = 0 ]
  [ "$(git config --global --get-regexp '^url\.' | grep -c .)" -eq 2 ]
}

@test "init removes an entry with the <token> placeholder" {
  printf 'Awea\nwearemd\n' >"$BATS_TEST_TMPDIR/ok.txt"
  git config --global 'url.https://x-access-token:<token>@github.com/Awea/.insteadOf' https://github.com/Awea/
  run "$INIT" < <(printf 'tokenA\ntokenW\n')
  [ "$status" -eq 0 ]
  run git config --global --get-regexp '^url\..*<token>'
  [ "$status" -ne 0 ]
  [ "$(git config --global url.https://x-access-token:tokenA@github.com/Awea/.insteadOf)" = https://github.com/Awea/ ]
}

@test "an empty token skips its owner, and a failed check tells it" {
  printf 'Awea\n' >"$BATS_TEST_TMPDIR/ok.txt"
  run "$INIT" < <(printf 'tokenA\n\n')
  [ "$status" -eq 1 ]
  [[ "$output" == *"wearemd: no token"* ]]
  run git config --global --get-regexp '^url\..*wearemd'
  [ "$status" -ne 0 ]
}

@test "init without a Claude login tells to run claude" {
  rm "$HOME/.claude/.credentials.json"
  printf 'Awea\nwearemd\n' >"$BATS_TEST_TMPDIR/ok.txt"
  run "$INIT" < <(printf 'tokenA\ntokenW\n')
  [ "$status" -eq 1 ]
  [[ "$output" == *"run claude"* ]]
}

@test "init calls the multica command of PATH when MULTICA_BIN is not set" {
  printf 'Awea\nwearemd\n' >"$BATS_TEST_TMPDIR/ok.txt"
  unset MULTICA_BIN
  run env PATH="$BATS_TEST_TMPDIR/fake:$PATH" "$INIT" < <(printf 'tokenA\ntokenW\n')
  [ "$status" -eq 0 ]
  grep -qxF 'multica workspace switch perso' "$LOG"
}

@test "init --reset asks again for the token of each owner" {
  printf 'Awea\nwearemd\n' >"$BATS_TEST_TMPDIR/ok.txt"
  "$INIT" < <(printf 'oldA\noldW\n') >/dev/null
  run "$INIT" --reset < <(printf 'newA\nnewW\n')
  [ "$status" -eq 0 ]
  [ "$(git config --global --get-regexp '^url\.' | grep -c .)" -eq 2 ]
  [ "$(git config --global url.https://x-access-token:newA@github.com/Awea/.insteadOf)" = https://github.com/Awea/ ]
  [ "$(git config --global url.https://x-access-token:newW@github.com/wearemd/.insteadOf)" = https://github.com/wearemd/ ]
}
