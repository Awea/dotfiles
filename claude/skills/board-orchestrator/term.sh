# shellcheck shell=bash
# The terminal layer of the board-orchestrator scripts: Rex only. lib.sh sources this file
# after it sets REX. Each term_X function calls rex_X. A terminal address is a Rex block ID
# ("block:..." or its last 8 hex digits).

# term_self: the address of the terminal of the caller.
term_self() { printf '%s\n' "${REX_BLOCK:-}"; }

# Calls with an address.
term_get() { rex_get "$@"; }
term_label() { rex_label "$@"; }
term_send() { rex_send "$@"; }
term_message() { rex_message "$@"; }
# term_post ADDR TEXT BOARD and term_tell ADDR TEXT BOARD: as term_send and term_message,
# for a message to the orchestrator of BOARD. It can wait in a queue until the user stops
# typing.
term_post() { rex_post "$@"; }
term_tell() { rex_tell "$@"; }
# term_can_queue ADDR, term_waiting ADDR and term_queue_message ADDR TEXT BOARD: words for
# a busy worker wait in the queue until it is idle. See rex_queue_message.
term_can_queue() { rex_can_queue "$@"; }
term_waiting() { rex_waiting "$@"; }
term_queue_message() { rex_queue_message "$@"; }
# term_prompt_state ADDR: empty, typed or none. See rex_prompt_state.
term_prompt_state() { rex_prompt_state "$@"; }
term_read() { rex_read "$@"; }
term_wait() { rex_wait "$@"; }
term_park() { rex_park "$@"; }
term_kill() { rex_kill "$@"; }
term_rm() { rex_rm "$@"; }
term_focus_agent() { rex_focus_agent "$@"; }
term_focus_pane() { rex_focus_pane "$@"; }
term_space_close() { rex_space_close "$@"; }

# Calls with no address.
term_names() { rex_names; }
term_ping() { rex_ping; }
term_run_worker() { rex_run_worker "$@"; }
term_space_new() { rex_space_new "$@"; }
term_tell_cmd() { rex_tell_cmd "$@"; }
term_tell_rule() { rex_tell_rule; }

# The Rex versions. A Rex block ID is "block:<uuid>". The short form is its last 8
# characters. A record in $(state_dir)/rex/<block ID>.json keeps the labels of the block:
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

# _rex_gone SESSION BLOCK: exit 0 only when Rex answers and SESSION does not list the full
# block ID BLOCK. A failed call is not a gone block.
_rex_gone() {
  local blocks
  blocks=$(_rex_api session.list_blocks "$(jq -cn --arg s "$1" '{session_id: $s}')") || return 1
  jq -e '.blocks | type == "array"' <<<"$blocks" >/dev/null 2>&1 || return 1
  ! jq -e --arg b "$2" 'any(.blocks[]; .block_id == $b)' <<<"$blocks" >/dev/null 2>&1
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

# rex_get ADDR: the answers of Rex in the shape of the old get JSON. Exit 1 when the block is gone.
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
# Claude Code then keep it as one input until the Enter. Exit 1 when the text did not go,
# exit 2 when the text went and the Enter did not.
rex_send() {
  local full session text=$2
  _rex_target "$1" || return 1
  case "$text" in
    *$'\n'* | *$'\r'*) text=$'\e[200~'"$text"$'\e[201~' ;;
  esac
  "${REX[@]}" send -s "$session" -b "$full" -- "$text" >/dev/null || return 1
  "${REX[@]}" send-key -s "$session" -b "$full" enter >/dev/null || return 2
}

# _rex_tag TEXT: TEXT tagged with the sender, as a message to an agent.
_rex_tag() {
  local self short name board
  self=$(term_self)
  short=$(rex_short "$self")
  board=${BOARD:-$(rex_record "$self" | jq -r '.board // empty')}
  name=${BOARD_NAME:-$(board_slug "$board")-orchestrator}
  printf '<rex from="%s %s">%s</rex>' "$short" "$name" "$1"
}

# rex_message ADDR TEXT: a message to an agent, tagged with the sender.
rex_message() { rex_send "$1" "$(_rex_tag "$2")"; }

# A message to an orchestrator waits in a queue until the user does not type in it. rex
# send types the text at the cursor, and its Enter sends the text of the user with it.
# Rex does not tell when a user types, so the board watcher reads the input box of
# Claude Code: each second, while the queue has lines, it runs dispatch.sh deliver.

# rex_outbox SESSION: the queue file of the messages to the orchestrators of SESSION. One
# JSON line for each message: {to: block ID, board, text, at: epoch seconds}.
rex_outbox() { printf '%s/rex/outbox-%s.jsonl\n' "$(state_dir)" "$1"; }

# _rex_watcher_args SESSION: the arguments of the live board watcher of SESSION. Exit 1
# when none runs. A reused pid does not count: the process must be a rex do of the
# watcher script for that session.
_rex_watcher_args() {
  local pid args
  pid=$(cat "$(state_dir)/rex/watch-$1.pid" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  args=$(ps -o args= -p "$pid" 2>/dev/null) || return 1
  [[ "$args" == *" do -s $1 "* ]] || return 1
  grep -Eq 'rex[^ ]*( --autostart=[a-z]+)? do .*board-watch\.lua' <<<"$args" || return 1
  printf '%s\n' "$args"
}

# board_socket: the path of the socket of the board service.
board_socket() {
  local dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
  printf '%s\n' "${BOARD_SOCKET:-${dir%/}/board.sock}"
}

# board_mailbox SESSION: exit 0 when the board service runs the mailbox of SESSION. The
# service delivers the outbox and makes the worker notices then. A missing socket, a
# refused connect, a close with no line, or a time-out (1 s) gives exit 1.
board_mailbox() {
  local req reply
  req=$(jq -cn --arg s "$1" '{v:1, mailbox:$s}') || return 1
  reply=$(perl -MIO::Socket::UNIX -e '
    my ($path, $req) = @ARGV;
    $SIG{ALRM} = sub { exit 1 };
    alarm 1;
    my $s = IO::Socket::UNIX->new(Peer => $path, Timeout => 1) or exit 1;
    $s->timeout(1);
    print $s "$req\n";
    my $line = <$s>;
    exit 1 unless defined $line;
    print $line;
  ' "$(board_socket)" "$req" 2>/dev/null) || return 1
  jq -e '.mailbox == true' <<<"$reply" >/dev/null 2>&1
}

# rex_queues SESSION: exit 0 when the board service runs the mailbox of SESSION, or the
# live watcher of SESSION delivers the queue. An older watcher has no outbox argument.
rex_queues() {
  local args
  board_mailbox "$1" && return 0
  args=$(_rex_watcher_args "$1") || return 1
  [[ "$args" == *" outbox="* ]]
}

# _rex_lock FILE and _rex_unlock FILE: a lock on FILE, as the folder FILE.lock with the pid
# of the holder in FILE.lock/pid. mkdir works on Linux and macOS, flock does not. A lock
# whose holder is dead is stale. A lock with no pid yet is stale after one minute. The
# lock takes BOARD_OUTBOX_LOCK_TRIES tries (default 100), 0.1 s apart. The unlock removes
# only a lock of the caller, so a second unlock (a trap) never removes the lock of another.
_rex_lock() {
  local lock="$1.lock" i=0 pid=""
  until mkdir "$lock" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt "${BOARD_OUTBOX_LOCK_TRIES:-100}" ]; then
      printf 'dispatch: the queue %s is locked by %s.\n' "$1" "${pid:-?}" >&2
      return 1
    fi
    pid=$(cat "$lock/pid" 2>/dev/null || true)
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } ||
      { [ -z "$pid" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }; then
      # Read the pid again: another caller can have taken the lock meanwhile.
      [ "$(cat "$lock/pid" 2>/dev/null || true)" != "$pid" ] || rm -rf "$lock"
      continue
    fi
    sleep 0.1
  done
  printf '%s\n' "${BASHPID:-$$}" >"$lock/pid"
}
_rex_unlock() {
  [ "$(cat "$1.lock/pid" 2>/dev/null || true)" != "${BASHPID:-$$}" ] || rm -rf "$1.lock"
}

# _rex_enqueue SESSION BLOCK BOARD TEXT [ROLE]: add TEXT for the full block ID BLOCK to the
# queue of SESSION. ROLE worker marks words for a worker: deliver sends them only to an idle
# or done worker, and never to another block.
_rex_enqueue() {
  local file
  file=$(rex_outbox "$1")
  _rex_lock "$file" || return 1
  jq -cn --arg t "$2" --arg b "$3" --arg x "$4" --arg r "${5:-}" --argjson at "$(date +%s)" \
    '{to: $t, board: $b, text: $x, at: $at} + (if $r != "" then {role: $r} else {} end)' >>"$file"
  _rex_unlock "$file"
}

# rex_post ADDR TEXT BOARD: send TEXT to the orchestrator ADDR of BOARD. When the watcher of
# its session delivers the queue, TEXT goes into the queue. Else it goes at once.
rex_post() {
  local full session
  if ! _rex_target "$1" || ! rex_queues "$session"; then
    rex_send "$1" "$2"
    return
  fi
  _rex_enqueue "$session" "$full" "$3" "$2"
}

# rex_tell ADDR TEXT BOARD: rex_post of TEXT tagged with the sender.
rex_tell() { rex_post "$1" "$(_rex_tag "$2")" "$3"; }

# rex_can_queue ADDR: exit 0 when the watcher of the session of ADDR delivers the queue.
rex_can_queue() {
  local full session
  _rex_target "$1" && rex_queues "$session"
}

# rex_waiting ADDR: exit 0 when the queue has words for ADDR that wait.
rex_waiting() {
  local full session file
  _rex_target "$1" || return 1
  file=$(rex_outbox "$session")
  [ -s "$file" ] || return 1
  jq -enR --arg t "$full" '[inputs | fromjson? | select(type == "object" and .to == $t)] | length > 0' \
    "$file" >/dev/null 2>&1
}

# rex_queue_message ADDR TEXT BOARD: TEXT tagged with the sender goes into the queue, for
# the worker ADDR of BOARD. Exit 1 when no watcher of its session delivers the queue.
rex_queue_message() {
  local full session
  _rex_target "$1" && rex_queues "$session" || return 1
  _rex_enqueue "$session" "$full" "$3" "$(_rex_tag "$2")" worker
}

# rex_prompt_state ADDR: the input box of the Claude Code in ADDR. empty: the box shows no
# typed text. typed: it shows typed text. none: no input box, for example in a dialog. The
# box is the lines between the last two rule lines that start with the prompt sign. A rule
# line starts with a run of ─: the top one can end with a label, such as the session name.
# Claude Code shows a suggestion as dim text in the box: the check skips dim text, so it
# reads the VT format, not the text format.
rex_prompt_state() {
  local full session
  if ! _rex_target "$1"; then printf 'none\n'; return 0; fi
  "${REX[@]}" capture -s "$session" -b "$full" --format vt 2>/dev/null | perl -e '
    my @all; my @text;
    while (defined(my $l = <STDIN>)) {
      $l =~ s/[\r\n]//g;
      my ($dim, $a, $t) = (0, "", "");
      while (length $l) {
        if ($l =~ s/^\e\[([0-9;:]*)m//) {
          my @p = split /[;:]/, $1, -1;
          @p = (0) unless @p;
          while (@p) {
            my $x = shift @p;
            $x = 0 if $x eq "";
            if ($x == 38 || $x == 48 || $x == 58) {
              my $k = shift(@p) // 0;
              splice @p, 0, ($k == 5 ? 1 : $k == 2 ? 3 : 0);
            } elsif ($x == 0 || $x == 22) { $dim = 0 }
            elsif ($x == 2) { $dim = 1 }
          }
        } elsif ($l =~ s/^\e\[(\d*)C//) {
          my $n = $1 eq "" ? 1 : $1;
          $a .= " " x $n; $t .= " " x $n;
        } elsif ($l =~ s/^\e\[[0-9;?:<=>]*[ -\/]*[@-~]//) {
        } elsif ($l =~ s/^\e[\]P_^].*?(?:\a|\e\\|$)//) {
        } elsif ($l =~ s/^\e.?//) {
        } else {
          $l =~ s/^([^\e]+)//;
          $a .= $1;
          $t .= $1 unless $dim;
        }
      }
      push @all, $a; push @text, $t;
    }
    my @r = grep { $all[$_] =~ /^\s*(?:\xe2\x94\x80){8,}/ } 0 .. $#all;
    for (my $i = $#r - 1; $i >= 0; $i--) {
      my ($top, $end) = ($r[$i], $r[$i + 1]);
      next unless $end > $top + 1 && $all[$top + 1] =~ /^\s*\xe2\x9d\xaf/;
      my $box = join " ", @text[$top + 1 .. $end - 1];
      $box =~ s/\xe2\x9d\xaf//;
      $box =~ s/\xc2\xa0/ /g;
      print $box =~ /\S/ ? "typed\n" : "empty\n";
      exit 0;
    }
    print "none\n";
  '
}

# _rex_ready ADDR [ROLE]: exit 0 when ADDR takes a message now: its input box is empty, and
# an orchestrator is not blocked. A worker (ROLE worker) must be idle or done: text typed
# into a permission prompt can select an option.
_rex_ready() {
  local st
  st=$(rex_get "$1" | jq -r '.status.state // empty') || return 1
  if [ "${2:-}" = worker ]; then
    case "$st" in idle | done) ;; *) return 1 ;; esac
  else
    [ "$st" != blocked ] || return 1
  fi
  [ "$(rex_prompt_state "$1")" = empty ]
}

# rex_deliver SESSION: send the queue of SESSION to each orchestrator or worker whose input
# box stayed empty for BOARD_OUTBOX_QUIET seconds (default 2). The watcher calls it each
# second while the queue has lines, so a user who types and stops for one second keeps the
# prompt. A worker gets its words only when it is idle or done. A message to a gone
# orchestrator goes to the live orchestrator of its board. With none, and for a gone
# worker, the message is dropped and stderr says so. A broken line of the queue is dropped. When a
# message waits for more than 5 minutes, stderr says it once. Exit 1 when a send fails:
# its messages stay. When only the Enter fails, the text is in the box: the messages are
# dropped, so that they do not go twice, and stderr says it. A kill of dispatch.sh deliver
# (the timeout of the watcher) does not stop this function: it runs in a subshell of
# dispatch.sh, so it trims the queue after a send.
rex_deliver() {
  local session=$1 file quiet=${BOARD_OUTBOX_QUIET:-2} to board addr text stamp since now
  local q oldest waits r role rc=0 done_to=()
  file=$(rex_outbox "$session")
  [ -s "$file" ] || return 0
  _rex_lock "$file" || return 1
  _rex_locked=$file
  trap '_rex_unlock "$_rex_locked"' EXIT
  trap 'exit 143' TERM INT HUP
  q=$(jq -cR 'fromjson? | select(type == "object" and (.to | type) == "string")' "$file")
  # The loop reads fd 3: the rex calls in it must not read the list.
  while IFS= read -r to <&3; do
    [ -n "$to" ] || continue
    board=$(jq -r --arg t "$to" 'select(.to == $t) | .board // empty' <<<"$q" | head -1)
    text=$(jq -r --arg t "$to" 'select(.to == $t) | .text' <<<"$q")
    oldest=$(jq -r --arg t "$to" 'select(.to == $t) | .at // empty' <<<"$q" | head -1)
    role=$(jq -r --arg t "$to" 'select(.to == $t) | .role // empty' <<<"$q" | head -1)
    now=$(date +%s)
    addr=$to
    if [ "$role" = worker ]; then
      if ! rex_get "$to" >/dev/null 2>&1; then
        # A failed Rex call keeps the words for the next check: drop them only when Rex
        # answers and its session does not list the block.
        _rex_gone "$session" "$to" || continue
        printf 'dispatch: the worker %s is gone. Dropped: %s\n' "$to" "$text" >&2
        rm -f "$file.quiet-$(rex_short "$to")" "$file.waits-$(rex_short "$to")"
        done_to+=("$to")
        continue
      fi
    elif ! rex_get "$to" >/dev/null 2>&1; then
      if ! addr=$(orchestrator_of "$board" 2>/dev/null) || ! rex_get "$addr" >/dev/null 2>&1; then
        printf 'dispatch: no orchestrator of the board %s runs. Dropped: %s\n' "$board" "$text" >&2
        done_to+=("$to")
        continue
      fi
    fi
    stamp="$file.quiet-$(rex_short "$addr")"
    waits="$file.waits-$(rex_short "$addr")"
    if ! _rex_ready "$addr" "$role"; then
      rm -f "$stamp"
      if [[ "$oldest" =~ ^[0-9]+$ ]] && [ $((now - oldest)) -ge 300 ] && [ ! -e "$waits" ]; then
        if [ "$role" = worker ]; then
          printf 'dispatch: words to the worker %s wait since %s s: it works or is blocked, or its input box is not empty, or it shows no box.\n' \
            "$addr" "$((now - oldest))" >&2
        else
          printf 'dispatch: a message to %s waits since %s s: its input box is not empty, or it is blocked or shows no box.\n' \
            "$addr" "$((now - oldest))" >&2
        fi
        : >"$waits"
      fi
      continue
    fi
    [ -f "$stamp" ] || printf '%s\n' "$now" >"$stamp"
    since=$(cat "$stamp")
    [ $((now - since)) -ge "$quiet" ] || continue
    r=0
    rex_send "$addr" "$text" || r=$?
    case "$r" in
      0)
        rm -f "$stamp" "$waits"
        done_to+=("$to")
        ;;
      2)
        printf 'dispatch: the Enter after the message to %s failed. The user must press Enter.\n' "$addr" >&2
        rm -f "$stamp" "$waits"
        done_to+=("$to")
        rc=1
        ;;
      *)
        printf 'dispatch: could not send to the %s %s.\n' "${role:-orchestrator}" "$addr" >&2
        rc=1
        ;;
    esac
  done 3< <(jq -r '.to' <<<"$q" | awk '!seen[$0]++')
  # Write the queue again: it drops the sent messages and the broken lines.
  if jq -c --args 'select(.to as $t | $ARGS.positional | index($t) | not)' ${done_to[@]+"${done_to[@]}"} \
    <<<"$q" >"$file.tmp.$$"; then
    mv "$file.tmp.$$" "$file"
  else
    rm -f "$file.tmp.$$"
    printf 'dispatch: could not write the queue %s.\n' "$file" >&2
    rc=1
  fi
  _rex_unlock "$file"
  return "$rc"
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
# does, through dispatch.sh notice. It also delivers the queue of rex_post. The pid file
# keeps the pid of its rex do process. The start is detached, and a wrapper writes the pid
# and then execs rex, so the pid stays. An older watcher with no queue is stopped first:
# two watchers would send each notice twice.
rex_watch() {
  local session=$1 dir pidfile here log
  [ -n "$session" ] || return 1
  dir="$(state_dir)/rex"
  mkdir -p "$dir"
  pidfile="$dir/watch-$session.pid"
  if _rex_watcher_args "$session" >/dev/null; then
    rex_queues "$session" && return 0
    kill "$(cat "$pidfile")" 2>/dev/null || true
  fi
  here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
  # shellcheck disable=SC2016 # The wrapper shell expands $$ and $1.
  local cmd=(bash -c 'echo $$ >"$1"; shift; exec "$@"' watch "$pidfile"
    "${REX[@]}" "do" -s "$session" "$here/board-watch.lua" "dispatch=$here/dispatch.sh" "session=$session"
    "outbox=$(rex_outbox "$session")")
  # The log keeps what the watcher says on stderr, so a failed notice leaves a trace.
  log="$dir/watch-$session.log"
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "${cmd[@]}" </dev/null >/dev/null 2>>"$log"
  else
    nohup "${cmd[@]}" </dev/null >/dev/null 2>>"$log" &
  fi
}
