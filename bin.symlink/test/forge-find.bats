#!/usr/bin/env bats
# Tests of forge-find. A fake curl, gh and bao on PATH log their arguments and their stdin,
# and print the fixture in $FIXTURE, so that no test calls a real forge.
# Run: ASDF_BATS_VERSION=1.8.2 bats bin.symlink/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  FF="$BATS_TEST_DIRNAME/../forge-find"
  LOG="$BATS_TEST_TMPDIR/log"
  FIXTURE="$BATS_TEST_TMPDIR/fixture.json"
  mkdir -p "$LOG" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/repo"
  for cmd in curl gh bao; do
    cat >"$BATS_TEST_TMPDIR/bin/$cmd" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$LOG/$cmd.args"
[ -t 0 ] || cat >"$LOG/$cmd.stdin"
if [ $cmd = bao ]; then printf '%s\n' "\${BAO_ADDR:-}" >"$LOG/bao.addr"; printf 'bao-token\n'; exit 0; fi
cat "$FIXTURE"
exit "\${FAKE_EXIT:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/$cmd"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" LOG FIXTURE
  export FORGEJO_ACCESS_TOKEN=env-token FORGE_FIND_FORGEJO_HOSTS=git.example.net
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  CONFIG="$XDG_CONFIG_HOME/forge-find/config"
  mkdir -p "${CONFIG%/*}"
  unset BAO_ADDR FORGE_FIND_BAO_PATH
  cd "$BATS_TEST_TMPDIR/repo" || return
  git init -q .
  git remote add origin ssh://forgejo@git.example.net:2222/own/app.git
  cat >"$FIXTURE" <<'EOF'
[{"number":1395,"state":"open","title":"Title","pull_request":null},
 {"number":1400,"state":"closed","title":"Other","pull_request":{"merged":true}},
 {"number":1401,"state":"closed","title":"Shut","pull_request":{"merged":false}}]
EOF
}

# url: the URL that the fake curl got (its last argument).
url() { tail -n 1 "$LOG/curl.args"; }

@test "Forgejo: lists issues and PRs on one line each" {
  run "$FF" -s all discovery tick
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "https://git.example.net/own/app" ]
  [ "${lines[1]}" = "#1395 open issue Title" ]
  [ "${lines[2]}" = "#1400 merged PR Other" ]
  [ "${lines[3]}" = "#1401 closed PR Shut" ]
  [[ "$(url)" == "https://git.example.net/api/v1/repos/own/app/issues?"* ]]
  [[ "$(url)" == *"q=discovery%20tick"* ]]
  [[ "$(url)" == *"state=all"* ]]
  [[ "$(url)" == *"limit=20"* ]]
  [[ "$(url)" != *"type="* ]]
}

@test "Forgejo: the default state is open, -t and -n set the type and the limit" {
  run "$FF" -t pulls -n 5
  [ "$status" -eq 0 ]
  [[ "$(url)" == *"state=open"* ]]
  [[ "$(url)" == *"type=pulls"* ]]
  [[ "$(url)" == *"limit=5"* ]]
  [[ "$(url)" != *"q="* ]]
}

@test "Forgejo: -i reads one issue" {
  echo '{"number":1395,"state":"open","title":"Title","pull_request":null}' >"$FIXTURE"
  run "$FF" -i 1395
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "#1395 open issue Title" ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(url)" = "https://git.example.net/api/v1/repos/own/app/issues/1395" ]
}

@test "Forgejo: the token goes to curl on stdin, not in its arguments" {
  run "$FF"
  [ "$status" -eq 0 ]
  if grep -q env-token "$LOG/curl.args"; then false; fi
  grep -qx 'Authorization: token env-token' "$LOG/curl.stdin"
}

@test "Forgejo: with no FORGEJO_ACCESS_TOKEN, bao gives the token" {
  unset FORGEJO_ACCESS_TOKEN
  export BAO_ADDR=https://bao.example.net
  run "$FF"
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' <"$LOG/bao.args")" = "kv get -field=token secret/forgejo/api-tokens/claude " ]
  grep -qx 'Authorization: token bao-token' "$LOG/curl.stdin"
}

@test "Forgejo: with no token and no BAO_ADDR, bao does not run" {
  unset FORGEJO_ACCESS_TOKEN
  run "$FF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BAO_ADDR"* ]]
  [ ! -e "$LOG/bao.args" ]
  [ ! -e "$LOG/curl.args" ]
}

@test "the config file gives the Forgejo hosts, the bao address and the bao path" {
  unset FORGEJO_ACCESS_TOKEN FORGE_FIND_FORGEJO_HOSTS
  printf '%s\n' '# private settings' 'FORGE_FIND_FORGEJO_HOSTS=git.other.net git.example.net' \
    'BAO_ADDR=https://bao.example.net' 'FORGE_FIND_BAO_PATH=secret/a=b' >"$CONFIG"
  run "$FF"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG/bao.addr")" = "https://bao.example.net" ]
  [ "$(tr '\n' ' ' <"$LOG/bao.args")" = "kv get -field=token secret/a=b " ]
  grep -qx 'Authorization: token bao-token' "$LOG/curl.stdin"
}

@test "an env var wins over the config file" {
  printf 'FORGE_FIND_FORGEJO_HOSTS=git.other.net\n' >"$CONFIG"
  run "$FF"
  [ "$status" -eq 0 ]
}

@test "the config file takes CRLF, spaces, quotes, export, a trailing = and no final newline" {
  unset FORGEJO_ACCESS_TOKEN FORGE_FIND_FORGEJO_HOSTS
  printf '%s\r\n' '  export FORGE_FIND_FORGEJO_HOSTS = "git.other.net git.example.net"' \
    "BAO_ADDR='https://bao.example.net'" >"$CONFIG"
  printf 'FORGE_FIND_BAO_PATH=secret/a=' >>"$CONFIG"
  run "$FF"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG/bao.addr")" = "https://bao.example.net" ]
  [ "$(tr '\n' ' ' <"$LOG/bao.args")" = "kv get -field=token secret/a= " ]
}

@test "in the config file, the last line of a key wins" {
  unset FORGE_FIND_FORGEJO_HOSTS
  printf '%s\n' 'FORGE_FIND_FORGEJO_HOSTS=git.other.net' 'FORGE_FIND_FORGEJO_HOSTS=git.example.net' >"$CONFIG"
  run "$FF"
  [ "$status" -eq 0 ]
}

@test "with no HOME and no XDG_CONFIG_HOME, GitHub still works" {
  git remote set-url origin git@github.com:o/r.git
  echo '{"items":[]}' >"$FIXTURE"
  run env -u HOME -u XDG_CONFIG_HOME "$FF"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "https://github.com/o/r" ]
}

@test "the config file is data: a command in it does not run" {
  unset FORGE_FIND_FORGEJO_HOSTS
  # shellcheck disable=SC2016 # The $( ) must stay text in the file.
  printf 'FORGE_FIND_FORGEJO_HOSTS=$(touch %s/ran)\nPATH=/nowhere\n' "$BATS_TEST_TMPDIR" >"$CONFIG"
  run "$FF"
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  [[ "$output" == *"not a known Forgejo host"* ]]
}

@test "with no env and no config file, no Forgejo host is known" {
  unset FORGE_FIND_FORGEJO_HOSTS
  run "$FF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$CONFIG"* ]]
  [ ! -e "$LOG/curl.args" ]
}

@test "reads the host and the repo of the three origin URL forms" {
  export FORGE_FIND_FORGEJO_HOSTS="git.example.net git.example.org"
  git remote set-url origin git@git.example.org:own/proj.git
  run "$FF"
  [ "${lines[0]}" = "https://git.example.org/own/proj" ]
  git remote set-url origin https://git.example.org/own/proj2
  run "$FF"
  [ "${lines[0]}" = "https://git.example.org/own/proj2" ]
  [[ "$(url)" == "https://git.example.org/api/v1/repos/own/proj2/issues?"* ]]
}

@test "-R and -H set the repo and the host" {
  git remote remove origin
  run "$FF" -R own/lib -H git.example.net
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "https://git.example.net/own/lib" ]
}

@test "no origin and no -R is a usage error" {
  git remote remove origin
  run "$FF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"-R owner/repo"* ]]
  [ ! -e "$LOG/curl.args" ]
}

@test "a title with a newline and a tab prints on one line" {
  printf '%s\n' '[{"number":1,"state":"open","title":"a\nb\tc","pull_request":null}]' >"$FIXTURE"
  run "$FF"
  [ "${lines[1]}" = "#1 open issue a b c" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "an API error prints the message of the forge" {
  echo '{"message":"token is required"}' >"$FIXTURE"
  FAKE_EXIT=22 run "$FF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"token is required"* ]]
}

@test "a host that is not a known forge gets no token" {
  unset FORGEJO_ACCESS_TOKEN
  git remote set-url origin git@gitlab.com:o/r.git
  run "$FF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"FORGE_FIND_FORGEJO_HOSTS"* ]]
  [ ! -e "$LOG/bao.args" ]
  [ ! -e "$LOG/curl.args" ]
}

@test "an error page that is not JSON is cut to 300 bytes" {
  head -c 5000 /dev/zero | tr '\0' x >"$FIXTURE"
  FAKE_EXIT=22 run "$FF"
  [ "$status" -eq 1 ]
  [ "${#output}" -lt 400 ]
}

@test "an unknown option is a usage error" {
  run "$FF" -z
  [ "$status" -eq 2 ]
}

@test "GitHub: searches with gh api" {
  git remote set-url origin git@github.com:o/r.git
  echo '{"items":[{"number":7,"state":"closed","title":"Fix","pull_request":{"merged_at":"2026-11-01T00:00:00Z"}}]}' >"$FIXTURE"
  run "$FF" -t pulls -n 3 some text
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "https://github.com/o/r" ]
  [ "${lines[1]}" = "#7 merged PR Fix" ]
  grep -qx 'search/issues' "$LOG/gh.args"
  grep -qx 'q=repo:o/r is:pr state:open some text' "$LOG/gh.args"
  grep -qx 'per_page=3' "$LOG/gh.args"
  [ ! -e "$LOG/curl.args" ]
}

@test "GitHub: -s all sends no state, -i reads one issue" {
  git remote set-url origin https://github.com/o/r.git
  echo '{"number":7,"state":"open","title":"Bug"}' >"$FIXTURE"
  run "$FF" -s all
  grep -qx 'q=repo:o/r' "$LOG/gh.args"
  run "$FF" -i 7
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "#7 open issue Bug" ]
  grep -qx 'repos/o/r/issues/7' "$LOG/gh.args"
}
