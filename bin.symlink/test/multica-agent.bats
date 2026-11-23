#!/usr/bin/env bats
# Tests of multica-agent, with fakes for sudo, getent, id, uname, systemctl, git and multica
# that log their argv and change nothing.
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  MA="$BATS_TEST_DIRNAME/../multica-agent"
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home" USER=awea
  mkdir -p "$HOME/.local/bin"
  chmod 750 "$HOME"
  LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$LOG"
  F="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$F"
  for c in sudo systemctl git; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >>%q\n' "$c" "$LOG" >"$F/$c"
  done
  # getent finds the user when the file user-exists is there; id lists the groups of
  # groups.txt; uname prints uname.txt.
  printf '#!/usr/bin/env bash\n[ -f %q ] && echo "multica-agent:x:30033:30033::/home/multica-agent:/bin/bash"\n' \
    "$BATS_TEST_TMPDIR/user-exists" >"$F/getent"
  printf '#!/usr/bin/env bash\ncat %q 2>/dev/null || echo awea\n' "$BATS_TEST_TMPDIR/groups.txt" >"$F/id"
  printf '#!/usr/bin/env bash\ncat %q 2>/dev/null || echo Linux\n' "$BATS_TEST_TMPDIR/uname.txt" >"$F/uname"
  printf '#!/usr/bin/env bash\nprintf "multica %%s\\n" "$*" >>%q\n' "$LOG" >"$HOME/.local/bin/multica"
  chmod +x "$F"/* "$HOME/.local/bin/multica"
  export SUDO_BIN="$F/sudo" GETENT_BIN="$F/getent" ID_BIN="$F/id" UNAME_BIN="$F/uname" \
    SYSTEMCTL_BIN="$F/systemctl" GIT_BIN="$F/git" PATH="$HOME/.local/bin:$PATH" \
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  LINKS="$XDG_DATA_HOME/multica/git"
  UNIT="$XDG_CONFIG_HOME/systemd/user/multica-git.service"
}

@test "setup makes the user, its group and home rights, and installs the files" {
  run "$MA" setup
  [ "$status" -eq 0 ]
  grep -qxF 'sudo useradd -m -s /bin/bash multica-agent' "$LOG"
  grep -qxF 'sudo usermod -aG multica-agent awea' "$LOG"
  grep -qxF 'sudo chmod 750 /home/multica-agent' "$LOG"
  grep -qxF "sudo install -D -o multica-agent -g multica-agent -m 644 $REPO/claude/CLAUDE.md /home/multica-agent/.claude/CLAUDE.md" "$LOG"
  grep -qxF "sudo install -D -o multica-agent -g multica-agent -m 755 $HOME/.local/bin/multica /home/multica-agent/.local/bin/multica" "$LOG"
  grep -qxF "sudo install -D -o multica-agent -g multica-agent -m 755 $REPO/multica/agent-init /home/multica-agent/.local/bin/multica-agent-init" "$LOG"
  grep -qF 'sudo -iu multica-agent bash -c ' "$LOG"
  grep -qF 'https://claude.ai/install.sh' "$LOG"
  grep -qxF 'sudo -iu multica-agent multica config set server_url http://localhost:8080' "$LOG"
  grep -qxF 'sudo -iu multica-agent multica config set app_url http://localhost:3200' "$LOG"
  [[ "$output" == *"multica-agent-init"* ]]
}

@test "setup never adds the agent to the docker or sudo group" {
  run "$MA" setup
  run grep -E 'usermod .*(docker|sudo)|useradd .*-G' "$LOG"
  [ "$status" -ne 0 ]
}

@test "setup skips the user and the group when they exist" {
  touch "$BATS_TEST_TMPDIR/user-exists"
  echo 'awea multica-agent docker' >"$BATS_TEST_TMPDIR/groups.txt"
  run "$MA" setup
  [ "$status" -eq 0 ]
  run grep -E 'useradd|usermod' "$LOG"
  [ "$status" -ne 0 ]
}

@test "setup closes a home that others can read" {
  chmod 755 "$HOME"
  run "$MA" setup
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$HOME" 2>/dev/null || stat -f %Lp "$HOME")" = 750 ]
  [[ "$output" == *"others"* ]]
}

@test "setup refuses with no multica command of the user" {
  rm "$HOME/.local/bin/multica"
  run env PATH="/usr/bin:/bin" "$MA" setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"README part 2"* ]]
  run grep -c 'install -D' "$LOG"
  [ "$output" = 0 ]
}

@test "setup is Linux only" {
  echo Darwin >"$BATS_TEST_TMPDIR/uname.txt"
  run "$MA" setup
  [ "$status" -eq 2 ]
  [ ! -s "$LOG" ]
}

@test "setup installs the systemd unit of the daemon" {
  run "$MA" setup
  [ "$status" -eq 0 ]
  grep -qxF "sudo install -D -o root -g root -m 644 $REPO/multica/multica-daemon.service /etc/systemd/system/multica-daemon.service" "$LOG"
  grep -qxF 'sudo systemctl daemon-reload' "$LOG"
}

@test "the unit runs the daemon as multica-agent in a login shell, five runs at a time" {
  unit="$REPO/multica/multica-daemon.service"
  grep -qxF 'User=multica-agent' "$unit"
  grep -qxF 'Environment=MULTICA_DAEMON_MAX_CONCURRENT_TASKS=5' "$unit"
  grep -qxF "ExecStart=/bin/bash -lc 'exec multica daemon start --foreground'" "$unit"
  grep -qxF 'Restart=on-failure' "$unit"
  grep -qxF 'WantedBy=multi-user.target' "$unit"
}

@test "daemon enables and starts the systemd service" {
  run "$MA" daemon
  [ "$status" -eq 0 ]
  grep -qxF 'sudo systemctl enable --now multica-daemon.service' "$LOG"
  run grep -c rex-resource "$LOG"
  [ "$output" = 0 ]
}

# make_repo DIR: a git repo with one commit.
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
}

@test "share links the repo, starts the git service and adds the repo to Multica" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  run "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  [ "$status" -eq 0 ]
  [ "$(readlink "$LINKS/alpha")" = "$(cd "$BATS_TEST_TMPDIR/code/alpha" && pwd -P)/.git" ]
  cmp "$REPO/multica/multica-git.service" "$UNIT"
  grep -qxF 'systemctl --user daemon-reload' "$LOG"
  grep -qxF 'systemctl --user enable multica-git.service' "$LOG"
  grep -qxF 'systemctl --user restart multica-git.service' "$LOG"
  grep -qxF 'multica repo add git://localhost/alpha' "$LOG"
  [[ "$output" == *"git://localhost/alpha"* ]]
  run grep -c '^sudo' "$LOG"
  [ "$output" = 0 ]
}

@test "share takes the top folder of the repo from a sub-folder" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  mkdir "$BATS_TEST_TMPDIR/code/alpha/src"
  run "$MA" share "$BATS_TEST_TMPDIR/code/alpha/src"
  [ "$status" -eq 0 ]
  [ "$(readlink "$LINKS/alpha")" = "$(cd "$BATS_TEST_TMPDIR/code/alpha" && pwd -P)/.git" ]
}

@test "share names a bare repo without its .git suffix" {
  git init -q --bare -b master "$BATS_TEST_TMPDIR/beta.git"
  make_repo "$BATS_TEST_TMPDIR/tmp"
  git -C "$BATS_TEST_TMPDIR/tmp" push -q "$BATS_TEST_TMPDIR/beta.git" HEAD:refs/heads/master
  run "$MA" share "$BATS_TEST_TMPDIR/beta.git"
  [ "$status" -eq 0 ]
  [ "$(readlink "$LINKS/beta")" = "$(cd "$BATS_TEST_TMPDIR/beta.git" && pwd -P)" ]
  grep -qxF 'multica repo add git://localhost/beta' "$LOG"
}

@test "share links the git folder of a linked worktree" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  git -C "$BATS_TEST_TMPDIR/code/alpha" worktree add -q -b wt "$BATS_TEST_TMPDIR/code/alpha-wt"
  run "$MA" share "$BATS_TEST_TMPDIR/code/alpha-wt"
  [ "$status" -eq 0 ]
  [ "$(readlink "$LINKS/alpha-wt")" = "$(cd "$BATS_TEST_TMPDIR/code/alpha" && pwd -P)/.git/worktrees/alpha-wt" ]
}

@test "share is safe to run again on the same repo" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  run "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  [ "$status" -eq 0 ]
  [ "$(readlink "$LINKS/alpha")" = "$(cd "$BATS_TEST_TMPDIR/code/alpha" && pwd -P)/.git" ]
}

@test "share refuses a second repo with the same name" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  make_repo "$BATS_TEST_TMPDIR/other/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  : >"$LOG"
  run "$MA" share "$BATS_TEST_TMPDIR/other/alpha"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/code/alpha"* ]]
  [ "$(readlink "$LINKS/alpha")" = "$(cd "$BATS_TEST_TMPDIR/code/alpha" && pwd -P)/.git" ]
  [ ! -s "$LOG" ]
}

@test "share refuses a folder that is not a git repo" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run "$MA" share "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 1 ]
  [ ! -e "$LINKS" ]
  [ ! -s "$LOG" ]
}

@test "share refuses a repo with no commit" {
  git init -q "$BATS_TEST_TMPDIR/empty"
  run "$MA" share "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit"* ]]
  [ ! -e "$LINKS/empty" ]
  [ ! -s "$LOG" ]
}

@test "share needs a folder" {
  run "$MA" share
  [ "$status" -eq 2 ]
}

@test "unshare removes the link and the Multica repo, and restarts the service" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  make_repo "$BATS_TEST_TMPDIR/code/beta"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/beta"
  : >"$LOG"
  run "$MA" unshare alpha
  [ "$status" -eq 0 ]
  [ ! -L "$LINKS/alpha" ]
  [ -L "$LINKS/beta" ]
  grep -qxF 'multica repo remove git://localhost/alpha' "$LOG"
  grep -qxF 'systemctl --user restart multica-git.service' "$LOG"
}

@test "unshare takes a shared name before a folder of the same name" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  make_repo "$BATS_TEST_TMPDIR/code/beta"
  mkdir "$BATS_TEST_TMPDIR/code/beta/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/beta"
  cd "$BATS_TEST_TMPDIR/code/beta"
  run "$MA" unshare alpha
  [ "$status" -eq 0 ]
  [ ! -L "$LINKS/alpha" ]
  [ -L "$LINKS/beta" ]
}

@test "unshare takes the folder of the repo too" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  run "$MA" unshare "$BATS_TEST_TMPDIR/code/alpha"
  [ "$status" -eq 0 ]
  [ ! -L "$LINKS/alpha" ]
}

@test "unshare of the last repo stops the git service" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  : >"$LOG"
  run "$MA" unshare alpha
  [ "$status" -eq 0 ]
  grep -qxF 'systemctl --user disable --now multica-git.service' "$LOG"
  run grep -c restart "$LOG"
  [ "$output" = 0 ]
}

@test "unshare refuses a repo that is not shared" {
  run "$MA" unshare nope
  [ "$status" -eq 1 ]
  [ ! -s "$LOG" ]
}

@test "serve runs git daemon on 127.0.0.1, read-only, for the shared repos only" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  make_repo "$BATS_TEST_TMPDIR/code/beta"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/beta"
  : >"$LOG"
  run "$MA" serve
  [ "$status" -eq 0 ]
  grep -qxF "git daemon --strict-paths --base-path=$LINKS --export-all --reuseaddr --listen=127.0.0.1 --port=9418 $LINKS/alpha $LINKS/beta" "$LOG"
  run grep -cE 'enable=receive-pack|--enable' "$LOG"
  [ "$output" = 0 ]
}

@test "serve refuses to run with no shared repo" {
  run "$MA" serve
  [ "$status" -eq 1 ]
  [ ! -s "$LOG" ]
}

@test "serve skips a file in the folder of links that is not a link" {
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  mkdir "$LINKS/stray"
  : >"$LOG"
  run "$MA" serve
  [ "$status" -eq 0 ]
  grep -qxF "git daemon --strict-paths --base-path=$LINKS --export-all --reuseaddr --listen=127.0.0.1 --port=9418 $LINKS/alpha" "$LOG"
}

@test "the git unit runs serve as the user and starts again on a failure" {
  unit="$REPO/multica/multica-git.service"
  grep -qxF 'ExecStart=%h/.bin/multica-agent serve' "$unit"
  grep -qxF 'Restart=on-failure' "$unit"
  grep -qxF 'WantedBy=default.target' "$unit"
  run grep -E '^User=' "$unit"
  [ "$status" -ne 0 ]
}

@test "the real server gives the shared repo and refuses a link or a repo inside it" {
  command -v git-daemon >/dev/null || [ -x "$(git --exec-path)/git-daemon" ] || skip "no git daemon"
  make_repo "$BATS_TEST_TMPDIR/code/alpha"
  make_repo "$BATS_TEST_TMPDIR/secret"
  make_repo "$BATS_TEST_TMPDIR/code/alpha/nested"
  ln -s "$BATS_TEST_TMPDIR/secret" "$BATS_TEST_TMPDIR/code/alpha/escape"
  "$MA" share "$BATS_TEST_TMPDIR/code/alpha"
  port=$((20000 + RANDOM % 10000))
  env -u GIT_BIN MULTICA_GIT_PORT="$port" "$MA" serve 3>&- &
  pid=$!
  for _ in $(seq 50); do
    git ls-remote "git://127.0.0.1:$port/alpha" >/dev/null 2>&1 && break
    sleep 0.1
  done
  run git clone -q "git://127.0.0.1:$port/alpha" "$BATS_TEST_TMPDIR/c1"
  ok=$status
  run git clone -q "git://127.0.0.1:$port/alpha/escape" "$BATS_TEST_TMPDIR/c2"
  escape=$status
  run git clone -q "git://127.0.0.1:$port/alpha/nested" "$BATS_TEST_TMPDIR/c3"
  nested=$status
  run git clone -q "git://127.0.0.1:$port/../secret" "$BATS_TEST_TMPDIR/c4"
  up=$status
  kill "$pid"
  [ "$ok" -eq 0 ]
  [ "$escape" -ne 0 ]
  [ "$nested" -ne 0 ]
  [ "$up" -ne 0 ]
}
