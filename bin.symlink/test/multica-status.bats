#!/usr/bin/env bats
# Tests of multica-perso status, with a fake docker and the fake multica CLI.
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

load multica-helper

setup() {
  multica_setup
  export DOCKER_BIN="$BATS_TEST_TMPDIR/docker"
  server_running 0
  mkdir -p "$V/_multica"
  printf '%s\n' '- [ ] mc-0123abcd with-agent PER-1: X → move to ⏳ Waiting On, context: in Multica PER-1' \
    '- [x] mc-11111111 status PER-2: Y → move to 🔨 In Progress' \
    '- [ ] mc-2222beef status PER-3: Z → move to 📥 Backlog' >"$V/_multica/perso.changes.md"
}

# server_running N: the fake docker lists N running containers of the project multica,
# and logs its argv.
server_running() {
  cat >"$DOCKER_BIN" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/docker.log"
for _ in \$(seq 1 $1); do echo c; done
EOF
  chmod +x "$DOCKER_BIN"
}

@test "status with the server down prints server: down and the open changes" {
  run "$MP" status
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'server: down\nchanges: 2 open')" ]
  [ ! -s "$FAKE_MULTICA_DIR/calls.log" ] || [ "$(fake_calls '^issue list')" -eq 0 ]
}

@test "status counts the issues by status" {
  server_running 3
  fake_issue '{"status": "todo"}'
  fake_issue '{"status": "todo"}'
  fake_issue '{"status": "done"}'
  fake_issue '{"status": "blocked"}'
  run "$MP" status
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'server: up (3 containers)\nissues: backlog 0, todo 2, in_progress 0, in_review 0, blocked 1, done 1\nchanges: 2 open')" ]
  grep -qxF 'ps -q --filter label=com.docker.compose.project=multica --filter status=running' "$BATS_TEST_TMPDIR/docker.log"
}
