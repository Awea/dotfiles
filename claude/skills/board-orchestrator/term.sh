# shellcheck shell=bash
# The terminal layer of the board-orchestrator scripts. lib.sh sources this file after it
# sets HC and HAPP. Each term_X function calls the backend version: hc_X for a herdr-app
# terminal. An address picks the backend (term_of). A call with no address uses the
# backend of the caller (term_here).

# term_of ADDR: the backend of the terminal ADDR. A Rex block ID is "block:..." or 8 hex digits.
term_of() {
  case "$1" in
    block:*) printf 'rex\n' ;;
    *)
      if [[ "$1" =~ ^[0-9a-f]{8}$ ]]; then printf 'rex\n'; else printf 'hc\n'; fi
      ;;
  esac
}

# term_here: the backend of the caller. BOARD_TERM wins, then the env of the terminal.
term_here() {
  if [ -n "${BOARD_TERM:-}" ]; then
    printf '%s\n' "$BOARD_TERM"
  elif [ -n "${HC_TERMINAL_ID:-}" ]; then
    printf 'hc\n'
  elif [ -n "${REX_BLOCK:-}" ]; then
    printf 'rex\n'
  else
    printf 'hc\n'
  fi
}

# term_self: the address of the terminal of the caller.
term_self() { printf '%s\n' "${HC_TERMINAL_ID:-${REX_BLOCK:-}}"; }

# Calls with an address.
term_get() { "$(term_of "$1")_get" "$@"; }
term_label() { "$(term_of "$1")_label" "$@"; }
term_send() { "$(term_of "$1")_send" "$@"; }
term_message() { "$(term_of "$1")_message" "$@"; }
term_read() { "$(term_of "$1")_read" "$@"; }
term_wait() { "$(term_of "$1")_wait" "$@"; }
term_park() { "$(term_of "$1")_park" "$@"; }
term_kill() { "$(term_of "$1")_kill" "$@"; }
term_rm() { "$(term_of "$1")_rm" "$@"; }
term_focus_agent() { "$(term_of "$1")_focus_agent" "$@"; }
term_focus_pane() { "$(term_of "$1")_focus_pane" "$@"; }
term_space_close() { "$(term_of "$1")_space_close" "$@"; }

# Calls with no address.
term_names() { "$(term_here)_names"; }
term_ping() { "$(term_here)_ping"; }
# term_ping_of ADDR: ping the backend of the terminal ADDR.
term_ping_of() { "$(term_of "$1")_ping"; }
term_run_worker() { "$(term_here)_run_worker" "$@"; }
term_space_new() { "$(term_here)_space_new" "$@"; }
term_tell_cmd() { "$(term_here)_tell_cmd" "$@"; }
term_tell_rule() { "$(term_here)_tell_rule"; }

# The hc versions.

# hc_get ADDR: the hc get JSON. Exit 1 when the terminal is gone.
hc_get() { "${HC[@]}" get "$1" --json 2>/dev/null; }

# hc_names: the names of the live terminals, one for each line.
hc_names() { "${HC[@]}" ls --json 2>/dev/null | jq -r '.terminals[]?.name // empty' 2>/dev/null; }

# hc_label ADDR KEY=VALUE...
hc_label() { "${HC[@]}" label "$@" >/dev/null; }

# hc_send ADDR TEXT: type TEXT and Enter.
hc_send() { "${HC[@]}" send "$1" "$2" >/dev/null; }

# hc_message ADDR TEXT: a message to an agent. For hc this is hc_send.
hc_message() { hc_send "$@"; }

hc_read() { "${HC[@]}" read "$1" 2>/dev/null; }

# hc_wait ADDR SECONDS: print the reason that the wait ended.
hc_wait() { "${HC[@]}" wait "$1" --timeout "$2" 2>/dev/null | jq -r '.reason // empty' 2>/dev/null; }

hc_park() { "${HAPP[@]}" "do" terminal.park --terminal "$1" >/dev/null 2>&1; }
hc_kill() { "${HC[@]}" kill "$1" >/dev/null 2>&1; }
hc_rm() { "${HC[@]}" rm "$1" >/dev/null 2>&1; }

# hc_ping: exit 1 and a message on stderr when hc does not answer.
hc_ping() {
  local err
  err=$("${HC[@]}" ls --json 2>&1 >/dev/null) || {
    printf 'hc does not answer: %s\n' "${err%%$'\n'*}" >&2
    return 1
  }
}

# hc_run_worker CWD NAME BOARD SESSION -- CMD...: start a worker. Print its address.
hc_run_worker() {
  local cwd=$1 name=$2 board=$3 session=$4 out
  shift 5
  out=$("${HC[@]}" run --json --bg --name "$name" --cwd "$cwd" \
    --label "board=$board" --label board.role=worker --label "board.session=$session" \
    -- "$@") || return 1
  jq -r '.address // empty' <<<"$out"
}

hc_focus_agent() { "${HAPP[@]}" "do" agent.focus --terminal "$1" >/dev/null; }
hc_focus_pane() { "${HAPP[@]}" "do" pane.focus --terminal "$1" >/dev/null; }

# hc_space_new BOARD VAULT: open the space of the orchestrator. Print its first terminal.
hc_space_new() {
  local out
  out=$("${HAPP[@]}" "do" space.new --name "$1 orchestrator" --folder "$2" --tab orchestrator) || return 1
  jq -r '.terminal // empty' <<<"$out"
}

# hc_space_close ADDR: close the herdr-app space of ADDR. Exit 2 when ADDR has no space,
# exit 1 when the close fails.
hc_space_close() {
  local space
  space=$(hc_labels "$1" | jq -r '.["herdr.space"] // empty')
  [ -n "$space" ] || return 2
  "${HAPP[@]}" "do" space.close --id "$space" --confirmed true >/dev/null || return 1
}

# hc_tell_cmd TEXT: the command that a worker runs to send TEXT to its orchestrator.
hc_tell_cmd() { printf 'hc send %s "%s"\n' "${HC_TERMINAL_ID:-}" "$1"; }

# hc_tell_rule: the allow rule for that command.
hc_tell_rule() { printf 'Bash(hc send %s *)\n' "${HC_TERMINAL_ID:-}"; }

# The Rex versions. A Rex block ID is "block:<uuid>". The short form is its last 8
# characters. A record in $(state_dir)/rex/<block ID>.json keeps what hc keeps in labels:
# {board, role, session, typed, rex_session, window, name}.

# _rex_api METHOD JSON: call a method of the Rex control API.
_rex_api() { "${REX[@]}" api call "$1" "$2" 2>/dev/null; }

# _rex_rec_file BLOCK: the path of the record of the full block ID BLOCK.
_rex_rec_file() { printf '%s/rex/%s.json\n' "$(state_dir)" "$1"; }

# _rex_blocks: one JSON line {session_id, block_id, window_id} for each live terminal block
# of each session.
_rex_blocks() {
  local s
  for s in $(_rex_api session.list '{}' | jq -r '.sessions[]?.session_id'); do
    _rex_api session.list_blocks "$(jq -cn --arg s "$s" '{session_id: $s}')" |
      jq -c --arg s "$s" '.blocks[]? | select(.creator_name == "com.superlogical.terminal")
        | {session_id: $s, block_id, window_id}'
  done
}

# rex_short ADDR: the last 8 characters of the block ID.
rex_short() { printf '%s\n' "${1: -8}"; }

# rex_full ADDR: the full block ID of a full ID or of an 8-hex suffix. The record file names
# come first, then the live blocks, then the workers file: the record and the block of an
# exited worker can be gone. Exit 1 when there is none.
rex_full() {
  local f full
  [ -n "$1" ] || return 1
  case "$1" in
    block:*) printf '%s\n' "$1"; return 0 ;;
  esac
  for f in "$(state_dir)"/rex/*"$1".json; do
    [ -f "$f" ] || continue
    full=$(basename "$f" .json)
    printf '%s\n' "$full"
    return 0
  done
  full=$(_rex_blocks | jq -r --arg s "$1" 'select(.block_id | endswith($s)) | .block_id' | head -1)
  if [ -z "$full" ] && [ -f "$(state_dir)/workers" ]; then
    full=$(awk -F '\t' -v s="$1" '$1 ~ /^block:/ && substr($1, length($1) - 7) == s { a = $1 } END { print a }' \
      "$(state_dir)/workers")
  fi
  [ -n "$full" ] || return 1
  printf '%s\n' "$full"
}

# _rex_live SESSION BLOCK: exit 0 when session.list_blocks has the block.
_rex_live() {
  _rex_api session.list_blocks "$(jq -cn --arg s "$1" '{session_id: $s}')" |
    jq -e --arg b "$2" 'any(.blocks[]?; .block_id == $b)' >/dev/null 2>&1
}

# rex_session_of ADDR: the Rex session of the block. The record first, then a search.
rex_session_of() {
  local full session
  full=$(rex_full "$1") || return 1
  if [ -f "$(_rex_rec_file "$full")" ]; then
    session=$(jq -r '.rex_session // empty' "$(_rex_rec_file "$full")" 2>/dev/null)
    if [ -n "$session" ]; then printf '%s\n' "$session"; return 0; fi
  fi
  session=$(_rex_blocks | jq -r --arg b "$full" 'select(.block_id == $b) | .session_id' | head -1)
  [ -n "$session" ] || return 1
  printf '%s\n' "$session"
}

# rex_record ADDR: the JSON of the record. Exit 1 when there is none or the block is gone.
rex_record() {
  local full session
  full=$(rex_full "$1") || return 1
  [ -f "$(_rex_rec_file "$full")" ] || return 1
  session=$(rex_session_of "$full") || return 1
  _rex_live "$session" "$full" || return 1
  cat "$(_rex_rec_file "$full")"
}

# rex_record_set BLOCK JSON: merge JSON into the record, and make it when there is none.
rex_record_set() {
  local full file old
  full=$(rex_full "$1") || return 1
  file=$(_rex_rec_file "$full")
  mkdir -p "$(dirname "$file")"
  old=$(cat "$file" 2>/dev/null || printf '{}')
  if jq -c --argjson n "$2" '. + $n' <<<"$old" >"$file.tmp.$$"; then
    mv "$file.tmp.$$" "$file"
  else
    rm -f "$file.tmp.$$"
    return 1
  fi
}

# rex_record_rm BLOCK: delete the record.
rex_record_rm() {
  local full
  full=$(rex_full "$1") || full=$1
  rm -f "$(_rex_rec_file "$full")"
}

# _rex_method SESSION BLOCK METHOD: the JSON of a terminal method of the block.
_rex_method() {
  _rex_api block.method "$(jq -cn --arg s "$1" --arg b "$2" --arg m "$3" \
    '{session_id: $s, block_id: $b, method: $m}')"
}

# rex_get ADDR: the answers of Rex in the shape of hc_get. Exit 1 when the block is gone.
rex_get() {
  local full session proc st rec
  full=$(rex_full "$1") || return 1
  session=$(rex_session_of "$full") || return 1
  _rex_live "$session" "$full" || return 1
  proc=$(_rex_method "$session" "$full" process) || return 1
  st=$(_rex_method "$session" "$full" program_status) || st='{}'
  rec=$(cat "$(_rex_rec_file "$full")" 2>/dev/null) || rec='{}'
  # Claude reports its version as the process name, so the name comes from the path.
  jq -cn --arg a "$full" --argjson p "$proc" --argjson st "$st" --argjson r "$rec" '
    def base: split("/") | last;
    {address: $a, state: "live",
     pid: $p.child.pid,
     argv: [$p.child.invoked_path],
     foreground: {name: ($p.foreground.invoked_path // "" | base), pid: $p.foreground.pid},
     status: ([$st.records[]? | select(.app != null)][0] // null | if . == null then {} else {app, state} end),
     labels: {board: $r.board, "board.role": $r.role, "board.session": $r.session,
              "board.typed": $r.typed} | with_entries(select(.value != null))}'
}

# rex_names: the window labels of the session of the caller.
rex_names() {
  _rex_api session.view "$(jq -cn --arg s "${REX_SESSION:-}" '{session_id: $s}')" |
    jq -r '.windows[]?.label // empty' 2>/dev/null
}

# rex_label ADDR KEY=VALUE...: board, board.role, board.session and board.typed go into the record.
rex_label() {
  local addr=$1 kv key field
  shift
  for kv in "$@"; do
    key=${kv%%=*}
    case "$key" in
      board) field=board ;;
      board.role) field=role ;;
      board.session) field=session ;;
      board.typed) field=typed ;;
      *) continue ;;
    esac
    rex_record_set "$addr" "$(jq -cn --arg f "$field" --arg v "${kv#*=}" '{($f): $v}')"
  done
}

# _rex_target ADDR: set the variables full and session for the block.
_rex_target() {
  full=$(rex_full "$1") || return 1
  session=$(rex_session_of "$full") || return 1
}

# rex_send ADDR TEXT: type TEXT and Enter. rex send types the raw bytes, and a newline
# submits the line before it. So a TEXT with a newline goes as one bracketed paste: zsh and
# Claude Code then keep it as one input until the Enter.
rex_send() {
  local full session text=$2
  _rex_target "$1" || return 1
  case "$text" in
    *$'\n'* | *$'\r'*) text=$'\e[200~'"$text"$'\e[201~' ;;
  esac
  "${REX[@]}" send -s "$session" -b "$full" -- "$text" >/dev/null || return 1
  "${REX[@]}" send-key -s "$session" -b "$full" enter >/dev/null
}

# rex_message ADDR TEXT: a message to an agent, tagged with the sender.
rex_message() {
  local self short name board
  self=$(term_self)
  if [ "$(term_of "$self")" = rex ]; then
    short=$(rex_short "$self")
    board=${BOARD:-$(rex_record "$self" | jq -r '.board // empty')}
  else
    short=$self
    board=${BOARD:-$( [ -z "$self" ] || hc_labels "$self" | jq -r '.board // empty')}
  fi
  name=${BOARD_NAME:-$(board_slug "$board")-orchestrator}
  rex_send "$1" "<rex from=\"$short $name\">$2</rex>"
}

rex_read() {
  local full session
  _rex_target "$1" || return 1
  "${REX[@]}" capture -s "$session" -b "$full" 2>/dev/null
}

# rex_wait ADDR SECONDS: print exit when the block is gone, status when the agent does not
# work, timeout after SECONDS. It never prints message.
rex_wait() {
  local start=$SECONDS json state
  while :; do
    if ! json=$(rex_get "$1"); then printf 'exit\n'; return 0; fi
    state=$(jq -r '.status.state // empty' <<<"$json")
    if [ "$state" != working ]; then printf 'status\n'; return 0; fi
    if [ $((SECONDS - start)) -ge "$2" ]; then printf 'timeout\n'; return 0; fi
    sleep "${BOARD_REX_POLL:-2}"
  done
}

rex_park() { :; }

rex_kill() {
  local full session
  _rex_target "$1" || return 1
  _rex_api block.close "$(jq -cn --arg s "$session" --arg b "$full" '{session_id: $s, block_id: $b}')" >/dev/null
}

rex_rm() { rex_record_rm "$1"; }

# rex_ping: exit 1 and a message on stderr when Rex does not answer.
rex_ping() {
  local err
  err=$("${REX[@]}" server status 2>&1 >/dev/null) || {
    printf 'rex does not answer: %s\n' "${err%%$'\n'*}" >&2
    return 1
  }
}

# rex_run_worker CWD NAME BOARD SESSION -- CMD...: start a worker window. Print its block ID.
rex_run_worker() {
  local cwd=$1 name=$2 board=$3 session=$4 out window block
  if [ "${5:-}" != "--" ]; then
    printf 'term: rex_run_worker needs -- before the command\n' >&2
    return 2
  fi
  shift 5
  out=$("${REX[@]}" window new -s "${REX_SESSION:-}" --cwd "$cwd" --focus=false --json "$name" -- \
    env "BOARD=$board" BOARD_ROLE=worker "BOARD_SESSION=$session" "BOARD_NAME=$name" \
    "BOARD_ORCHESTRATOR=${REX_BLOCK:-}" "$@") || return 1
  window=$(jq -r '.window_id // empty' <<<"$out")
  block=$(jq -r '.block_ids[0] // empty' <<<"$out")
  [ -n "$block" ] || return 1
  rex_record_set "$block" "$(jq -cn --arg b "$board" --arg s "$session" --arg rs "${REX_SESSION:-}" \
    --arg w "$window" --arg n "$name" \
    '{board: $b, role: "worker", session: $s, rex_session: $rs, window: $w, name: $n}')"
  printf '%s\n' "$block"
}

# rex_show SESSION WINDOW: show the window to the client of the caller, when there is one.
rex_show() {
  [ -n "${REX_CLIENT:-}" ] || return 0
  "${REX[@]}" -C "$REX_CLIENT" "do" session.select \
    --args "$(jq -cn --arg s "$1" --arg w "$2" '{session_id: $s, window_id: $w}')" >/dev/null
}

# rex_space_new BOARD VAULT: open the session of the orchestrator. Print its block ID.
rex_space_new() {
  local out session window block
  out=$("${REX[@]}" new "$1 orchestrator" --window orchestrator --cwd "$2" --json) || return 1
  session=$(jq -r '.session_id // empty' <<<"$out")
  window=$(jq -r '.initial_windows[0].window_id // empty' <<<"$out")
  block=$(jq -r '.initial_windows[0].block_ids[0] // empty' <<<"$out")
  [ -n "$block" ] || return 1
  rex_record_set "$block" "$(jq -cn --arg b "$1" --arg s "$session" --arg w "$window" \
    '{board: $b, role: "orchestrator", rex_session: $s, window: $w}')"
  rex_show "$session" "$window" || true
  printf '%s\n' "$block"
}

# rex_focus_pane ADDR: show the window of the block and focus the block.
rex_focus_pane() {
  local full session window
  _rex_target "$1" || return 1
  window=$(jq -r '.window // empty' "$(_rex_rec_file "$full")" 2>/dev/null)
  if [ -z "$window" ]; then
    window=$(_rex_blocks | jq -r --arg b "$full" 'select(.block_id == $b) | .window_id' | head -1)
  fi
  rex_show "$session" "$window" || true
  _rex_api session.focus_block "$(jq -cn --arg s "$session" --arg b "$full" '{session_id: $s, block_id: $b}')" >/dev/null
}
rex_focus_agent() { rex_focus_pane "$@"; }

# rex_space_close ADDR: kill the session of ADDR, and delete the record of ADDR. Exit 2 when
# there is no session to close: the block is unknown or has no orchestrator record (a worker
# shares the session of the orchestrator). Exit 1 when the kill fails: the record stays.
# The record goes before the kill: when the caller runs in that session, the kill ends the
# caller.
rex_space_close() {
  local full session rec
  full=$(rex_full "$1") || return 2
  session=$(rex_session_of "$full") || return 2
  rec=$(cat "$(_rex_rec_file "$full")" 2>/dev/null) || return 2
  [ "$(jq -r '.role // empty' <<<"$rec" 2>/dev/null)" = orchestrator ] || return 2
  rm -f "$(_rex_rec_file "$full")"
  if ! "${REX[@]}" kill "$session" >/dev/null 2>&1; then
    printf '%s\n' "$rec" >"$(_rex_rec_file "$full")"
    return 1
  fi
}

# rex_tell_cmd TEXT: the command that a worker runs to send TEXT to its orchestrator. The
# path is absolute: the allow rule must match the command that the worker types.
rex_tell_cmd() { printf '%s/.claude/skills/board-orchestrator/dispatch.sh tell "%s"\n' "$HOME" "$1"; }

# rex_tell_rule: the allow rule for that command.
rex_tell_rule() { printf 'Bash(%s/.claude/skills/board-orchestrator/dispatch.sh tell *)\n' "$HOME"; }

# rex_watch SESSION: make sure that one board watcher listens to the Rex session SESSION.
# Rex does not tell an orchestrator that a worker is blocked or exited: board-watch.lua
# does, through dispatch.sh notice. The pid file keeps the pid of its rex do process. The
# start is detached, and a wrapper writes the pid and then execs rex, so the pid stays.
rex_watch() {
  local session=$1 dir pidfile pid here log
  [ -n "$session" ] || return 1
  dir="$(state_dir)/rex"
  mkdir -p "$dir"
  pidfile="$dir/watch-$session.pid"
  pid=$(cat "$pidfile" 2>/dev/null || true)
  # A reused pid does not count: the process must be a rex do of the watcher script.
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null &&
    ps -o args= -p "$pid" 2>/dev/null | grep -Fq " do -s $session " &&
    ps -o args= -p "$pid" 2>/dev/null | grep -Eq 'rex[^ ]*( --autostart=[a-z]+)? do .*board-watch\.lua'; then
    return 0
  fi
  here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
  # shellcheck disable=SC2016 # The wrapper shell expands $$ and $1.
  local cmd=(bash -c 'echo $$ >"$1"; shift; exec "$@"' watch "$pidfile"
    "${REX[@]}" "do" -s "$session" "$here/board-watch.lua" "dispatch=$here/dispatch.sh" "session=$session")
  # The log keeps what the watcher says on stderr, so a failed notice leaves a trace.
  log="$dir/watch-$session.log"
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "${cmd[@]}" </dev/null >/dev/null 2>>"$log"
  else
    nohup "${cmd[@]}" </dev/null >/dev/null 2>>"$log" &
  fi
}
