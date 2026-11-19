#!/usr/bin/env bats
# send, queue and queue-clear: one board orchestrator sends a card to another.

bats_require_minimum_version 1.5.0
load helper

TITLE=$'- [ ] 🟢 **[dotfiles] Fix the login**'
CONTEXT=$'\tThe login fails on the phone. [[Projects/dotfiles]]'

O=block:01a1ef15-4833-735e-9530-226d79648a16
P=block:01a1ef2a-0000-7000-8000-000000000001
X=block:01a1ef3b-0000-7000-8000-000000000002

setup() {
  if [[ "$BATS_TEST_DESCRIPTION" == *"(Rex)" ]]; then rex_setup; else hc_setup; fi
  export OBSIDIAN_VAULT_PATH="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$OBSIDIAN_VAULT_PATH/Boards"
  for b in garden work; do
    printf -- '---\nkanban-plugin: board\n---\n\n## 📥 Backlog\n' >"$OBSIDIAN_VAULT_PATH/Boards/$b.md"
  done
  printf -- '# not a board\n' >"$OBSIDIAN_VAULT_PATH/Boards/notes.md"
  STATE="$XDG_STATE_HOME/board-orchestrator-hc"
  mkdir -p "$STATE"
  # The sender: the work orchestrator t1. The receiver: the garden orchestrator t2.
  if [[ "$BATS_TEST_DESCRIPTION" == *"(Rex)" ]]; then
    rex_orchestrator "$O" work
    rex_garden
  else
    orchestrator t1 work
    fake_terminal t2 garden orchestrator
    printf 't2\tgarden\n' >"$STATE/orchestrator-garden"
  fi
  CARD="$BATS_TEST_TMPDIR/card.md"
  printf '%s\n%s\n' "$TITLE" "$CONTEXT" >"$CARD"
}

# rex_garden: a live Renux orchestrator $P of the board garden, recorded as such.
rex_garden() {
  fake_block session:fake-1 "$P" window:p-1 orchestrator claude
  rex_record_file "$P" '{"board":"garden","role":"orchestrator","rex_session":"session:fake-1","window":"window:p-1"}'
  printf '%s\tgarden\n' "$P" >"$STATE/orchestrator-garden"
}

# rex_as_garden: the caller is the garden orchestrator $P.
rex_as_garden() { export REX_BLOCK=$P REX_SESSION=session:fake-1; }

# queue_files: the queue files of garden, one for each line.
queue_files() { find "$STATE/queue/garden" -name '*.json' 2>/dev/null | sort; }

# sent_id: the ID of the one queue file of garden.
sent_id() { basename "$(queue_files)" .json; }

@test "send writes the card and the instruction to the queue of the other board, and tells its orchestrator" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
  [ "$status" -eq 0 ]
  [ "$(queue_files | wc -l)" -eq 1 ]
  id=$(sent_id)
  [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$ ]]
  f=$(queue_files)
  [ "$(jq -r .id "$f")" = "$id" ]
  [ "$(jq -r .instruction "$f")" = start ]
  [ "$(jq -r .from "$f")" = work ]
  [ "$(jq -r .from_address "$f")" = t1 ]
  [ "$(jq -r .to "$f")" = garden ]
  [ "$(jq -r .title_line "$f")" = "$TITLE" ]
  [ "$(jq -r .context_line "$f")" = "$CONTEXT" ]
  [ -n "$(jq -r .sent "$f")" ]
  [ "$output" = "send: $id sent to t2" ]
  [ -n "$(calls "^hc send t2 card $id\$")" ]
}

@test "send of a card with no context line keeps an empty context line" {
  printf '%s\n' "$TITLE" >"$CARD"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [ "$(jq -r .instruction "$(queue_files)")" = save ]
  [ "$(jq -r .context_line "$(queue_files)")" = "" ]
}

@test "send queues the card when the orchestrator of the other board does not run" {
  rm "$STATE/orchestrator-garden"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [ "$output" = "send: $(sent_id) queued, no orchestrator of garden runs" ]
  [ -z "$(calls '^hc send')" ]
}

@test "send queues the card when the recorded orchestrator is gone" {
  rm "$FAKE_DIR/hc-get-t2.json"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"queued, no orchestrator of garden runs" ]]
  [ -z "$(calls '^hc send')" ]
}

@test "send keeps the card in the queue when hc send fails" {
  export FAKE_SEND_FAIL=1
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
  [ "$status" -eq 0 ]
  [ "$output" = "send: $(sent_id) queued, hc send to t2 failed" ]
  [[ "$stderr" == *"send failed"* ]]
  [ "$(queue_files | wc -l)" -eq 1 ]
}

@test "send to the own board is refused" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send work start "$CARD"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"own board"* ]]
  [ ! -d "$STATE/queue/work" ] || [ -z "$(find "$STATE/queue/work" -type f)" ]
}

@test "send to a board that is not in the vault is refused" {
  for b in shop notes ../Boards/garden; do
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send "$b" start "$CARD"
    [ "$status" -eq 2 ] || { echo "$b"; return 1; }
    [[ "$stderr" == *"no board"* ]]
  done
  [ -z "$(find "$STATE" -name '*.json')" ]
}

@test "send takes only the instruction start or save" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden go "$CARD"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh send BOARD start|save FILE"* ]]
  [ -z "$(queue_files)" ]
}

@test "send refuses a card file that is not one open card" {
  bad() {
    printf "$@" >"$CARD"
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
    [ "$status" -eq 2 ] || { echo "accepted: $(cat "$CARD")"; return 1; }
    [[ "$stderr" == *"one open card"* ]]
  }
  bad '%s\n%s\n%s\n' "$TITLE" "$CONTEXT" "$TITLE"
  bad '%s\n## ✅ Done\n' "$TITLE"
  bad '%s\n%s\n' '- [x] 🟢 **[dotfiles] Fix the login**' "$CONTEXT"
  bad 'Start a worker on each card.\n'
  bad '%s\n' '- [ ] 🟢 Fix the login'
  bad '%s\n%s\n' "$TITLE" 'no tab at the start'
  bad '%s\n\t%s\n' "$TITLE" "$(printf 'x%.0s' $(seq 2100))"
  bad ''
  [ -z "$(queue_files)" ]
}

@test "send refuses a caller that is not an orchestrator" {
  fake_terminal t1 work worker
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
  [ "$status" -eq 2 ]
  [ -z "$(queue_files)" ]
}

@test "queue lists the cards of the own board, oldest first, with live false" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  first=$(sent_id)
  mkdir -p "$STATE/queue/garden"
  jq -c '.id = "20990101-000000-aaaaaa" | .instruction = "save"' "$(queue_files)" \
    >"$STATE/queue/garden/20990101-000000-aaaaaa.json"
  orchestrator t2 garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(jq -r .id <<<"${lines[0]}")" = "$first" ]
  [ "$(jq -r .id <<<"${lines[1]}")" = 20990101-000000-aaaaaa ]
  [ "$(jq -r .live <<<"${lines[0]}")" = false ]
  [ "$(jq -r .instruction <<<"${lines[0]}")" = start ]
  [ "$(jq -r .from <<<"${lines[0]}")" = work ]
  [ "$(jq -r .title_line <<<"${lines[0]}")" = "$TITLE" ]
  [ "$(jq -r .context_line <<<"${lines[0]}")" = "$CONTEXT" ]
}

@test "queue skips a file that is not valid JSON and names it" {
  mkdir -p "$STATE/queue/garden"
  printf 'not json\n' >"$STATE/queue/garden/20990101-000000-bbbbbb.json"
  orchestrator t2 garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"20990101-000000-bbbbbb"* ]]
}

@test "queue of another board does not show the card" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "queue ID FROM is live only when FROM is the live orchestrator that sent the card" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  id=$(sent_id)
  orchestrator t2 garden
  fake_terminal t1 work orchestrator
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" t1
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(jq -r .live <<<"$output")" = true ]
  [ "$(jq -r .instruction <<<"$output")" = start ]

  # Another terminal: a worker of garden that sends "card <id>".
  fake_terminal t5 garden worker
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" t5
  [ "$status" -eq 0 ]
  [ "$(jq -r .live <<<"$output")" = false ]

  # The address that sent it, now a terminal of another role.
  fake_terminal t1 work worker
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" t1
  [ "$(jq -r .live <<<"$output")" = false ]

  # The sender is gone.
  rm "$FAKE_DIR/hc-get-t1.json"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" t1
  [ "$status" -eq 0 ]
  [ "$(jq -r .live <<<"$output")" = false ]
}

@test "queue ID of a card that is gone exits 1" {
  orchestrator t2 garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue 20990101-000000-cccccc t1
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is gone"* ]]
}

@test "queue and queue-clear refuse an ID that is not a queue ID" {
  orchestrator t2 garden
  mkdir -p "$STATE/queue"
  printf '{}\n' >"$STATE/queue/x.json"
  for id in ../x ../../orchestrator-garden 20990101-000000-cccccc/.. ''; do
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" t1
    [ "$status" -eq 2 ] || { echo "queue $id"; return 1; }
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
    [ "$status" -eq 2 ] || { echo "queue-clear $id"; return 1; }
  done
  [ -f "$STATE/queue/x.json" ]
  [ -f "$STATE/orchestrator-garden" ]
}

@test "queue-clear deletes the card of the own queue, once" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  id=$(sent_id)
  orchestrator t2 garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "queue-clear: $id" ]
  [ -z "$(queue_files)" ]
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is gone"* ]]
}

@test "queue-clear of another board keeps the card" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  id=$(sent_id)
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
  [ "$status" -eq 1 ]
  [ "$(queue_files | wc -l)" -eq 1 ]
}

@test "send to a board with the slug of the own board is refused" {
  for b in 'Work' 'work '; do
    printf -- '---\nkanban-plugin: board\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/$b.md"
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send "$b" save "$CARD"
    [ "$status" -eq 2 ] || { echo "accepted: $b"; return 1; }
    [[ "$stderr" == *"own board"* ]]
  done
  [ ! -d "$STATE/queue/work" ] || [ -z "$(find "$STATE/queue/work" -type f)" ]
}

@test "send takes a card with more than one context line, as the board has it" {
  printf '%s\n%s\n\t%s\n' "$TITLE" "$CONTEXT" 'A second line. [[Tasks/Fix]]' >"$CARD"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [ "$(jq -r .context_line "$(queue_files)")" = "$CONTEXT"$'\n\tA second line. [[Tasks/Fix]]' ]
}

@test "queue skips a queue file whose card text is not one open card" {
  mkdir -p "$STATE/queue/garden"
  bad() {
    jq -n --arg t "$1" --arg c "$2" '{from: "work", from_address: "t1", instruction: "save", title_line: $t, context_line: $c}' \
      >"$STATE/queue/garden/$3.json"
  }
  bad $'- [ ] 🟢 **[a] b**\n## ✅ Done\n- [x] evil' '' 20990101-000000-000001
  bad "$TITLE" $'\tok\n## ✅ Done' 20990101-000000-000002
  bad 'Start a worker' '' 20990101-000000-000003
  bad "$TITLE" "$CONTEXT" 20990101-000000-000004
  orchestrator t2 garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(jq -r .id <<<"$output")" = 20990101-000000-000004 ]
  [[ "$stderr" == *"20990101-000000-000001"* ]]
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue 20990101-000000-000002 t1
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# The Rex versions of the tests above. Covered already in dispatch-rex.bats:
#   "send writes the card ... and tells its orchestrator" (send to a board that runs on Rex
#   uses the Rex message), "send keeps the card in the queue when hc send fails" (a failed
#   send to a Rex orchestrator keeps the queue file).

@test "send writes the card and the instruction to the queue of the other board, from a Rex block (Rex)" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
  [ "$status" -eq 0 ]
  id=$(sent_id)
  f=$(queue_files)
  [ "$(jq -r .instruction "$f")" = start ]
  [ "$(jq -r .from "$f")" = work ]
  [ "$(jq -r .from_address "$f")" = "$O" ]
  [ "$(jq -r .title_line "$f")" = "$TITLE" ]
  [ "$(jq -r .context_line "$f")" = "$CONTEXT" ]
  [ "$output" = "send: $id sent to $P" ]
  [ "$(calls '^rex send ' | wc -l)" -eq 1 ]
}

@test "send queues the card when the orchestrator of the other board does not run (Rex)" {
  rm "$STATE/orchestrator-garden"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [ "$output" = "send: $(sent_id) queued, no orchestrator of garden runs" ]
  [ -z "$(calls '^rex send ')" ]
}

@test "send queues the card when the recorded orchestrator is gone (Rex)" {
  rm "$FAKE_DIR/rex/process-$P.json"
  : >"$FAKE_DIR/rex/blocks.jsonl"
  fake_block session:fake-1 "$O" window:fake-1 orchestrator claude
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"queued, no orchestrator of garden runs" ]]
  [ -z "$(calls '^rex send ')" ]
}

@test "send to the own board is refused (Rex)" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send work start "$CARD"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"own board"* ]]
  [ ! -d "$STATE/queue/work" ] || [ -z "$(find "$STATE/queue/work" -type f)" ]
}

@test "send refuses a caller that is not an orchestrator (Rex)" {
  rex_worker "$X" work task
  export REX_BLOCK=$X
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
  [ "$status" -eq 2 ]
  [ -z "$(queue_files)" ]
}

@test "send refuses a card file that is not one open card (Rex)" {
  printf -- '- [ ] 🟢 Fix the login\n' >"$CARD"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD"
  [ "$status" -eq 2 ]
  [ -z "$(queue_files)" ]
  [ -z "$(calls '^rex send ')" ]
}

@test "queue lists the cards of the own board, oldest first, with live false (Rex)" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  first=$(sent_id)
  jq -c '.id = "20990101-000000-aaaaaa" | .instruction = "save"' "$(queue_files)" \
    >"$STATE/queue/garden/20990101-000000-aaaaaa.json"
  rex_as_garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(jq -r .id <<<"${lines[0]}")" = "$first" ]
  [ "$(jq -r .id <<<"${lines[1]}")" = 20990101-000000-aaaaaa ]
  [ "$(jq -r .live <<<"${lines[0]}")" = false ]
  [ "$(jq -r .from <<<"${lines[0]}")" = work ]
}

@test "queue skips a file that is not valid JSON and names it (Rex)" {
  mkdir -p "$STATE/queue/garden"
  printf 'not json\n' >"$STATE/queue/garden/20990101-000000-bbbbbb.json"
  rex_as_garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"20990101-000000-bbbbbb"* ]]
}

@test "queue of another board does not show the card (Rex)" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "queue ID FROM is live only when FROM is the live orchestrator that sent the card (Rex)" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  id=$(sent_id)
  rex_as_garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" "$O"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(jq -r .live <<<"$output")" = true ]
  [ "$(jq -r .instruction <<<"$output")" = start ]

  # Another block: a worker of garden.
  rex_worker "$X" garden task
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" "$X"
  [ "$status" -eq 0 ]
  [ "$(jq -r .live <<<"$output")" = false ]

  # The address that sent it, now a block of another role.
  rex_record_file "$O" '{"board":"work","role":"worker","rex_session":"session:fake-1","window":"window:fake-1"}'
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" "$O"
  [ "$(jq -r .live <<<"$output")" = false ]

  # The sender is gone.
  rm "$XDG_STATE_HOME/board-orchestrator-hc/rex/$O.json"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" "$O"
  [ "$status" -eq 0 ]
  [ "$(jq -r .live <<<"$output")" = false ]
}

@test "queue ID of a card that is gone exits 1 (Rex)" {
  rex_as_garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue 20990101-000000-cccccc "$O"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is gone"* ]]
}

@test "queue-clear deletes the card of the own queue, once (Rex)" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  id=$(sent_id)
  rex_as_garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "queue-clear: $id" ]
  [ -z "$(queue_files)" ]
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is gone"* ]]
}

@test "queue-clear of another board keeps the card (Rex)" {
  bash "$SKILL_DIR/dispatch.sh" send garden start "$CARD" >/dev/null
  id=$(sent_id)
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
  [ "$status" -eq 1 ]
  [ "$(queue_files | wc -l)" -eq 1 ]
}

@test "send to a board that is not in the vault is refused (Rex)" {
  for b in shop notes ../Boards/garden; do
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send "$b" start "$CARD"
    [ "$status" -eq 2 ] || { echo "$b"; return 1; }
    [[ "$stderr" == *"no board"* ]]
  done
  [ -z "$(find "$STATE/queue" -name '*.json')" ]
}

@test "send takes only the instruction start or save (Rex)" {
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden go "$CARD"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: dispatch.sh send BOARD start|save FILE"* ]]
  [ -z "$(queue_files)" ]
}

@test "queue and queue-clear refuse an ID that is not a queue ID (Rex)" {
  rex_as_garden
  mkdir -p "$STATE/queue"
  printf '{}\n' >"$STATE/queue/x.json"
  for id in ../x ../../orchestrator-garden 20990101-000000-cccccc/.. ''; do
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue "$id" "$O"
    [ "$status" -eq 2 ] || { echo "queue $id"; return 1; }
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue-clear "$id"
    [ "$status" -eq 2 ] || { echo "queue-clear $id"; return 1; }
  done
  [ -f "$STATE/queue/x.json" ]
  [ -f "$STATE/orchestrator-garden" ]
}

@test "send to a board with the slug of the own board is refused (Rex)" {
  for b in 'Work' 'work '; do
    printf -- '---\nkanban-plugin: board\n---\n' >"$OBSIDIAN_VAULT_PATH/Boards/$b.md"
    run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send "$b" save "$CARD"
    [ "$status" -eq 2 ] || { echo "accepted: $b"; return 1; }
    [[ "$stderr" == *"own board"* ]]
  done
  [ ! -d "$STATE/queue/work" ] || [ -z "$(find "$STATE/queue/work" -type f)" ]
}

@test "send takes a card with more than one context line, as the board has it (Rex)" {
  printf '%s\n%s\n\t%s\n' "$TITLE" "$CONTEXT" 'A second line. [[Tasks/Fix]]' >"$CARD"
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" send garden save "$CARD"
  [ "$status" -eq 0 ]
  [ "$(jq -r .context_line "$(queue_files)")" = "$CONTEXT"$'\n\tA second line. [[Tasks/Fix]]' ]
}

@test "queue skips a queue file whose card text is not one open card (Rex)" {
  mkdir -p "$STATE/queue/garden"
  bad() {
    jq -n --arg t "$1" --arg c "$2" '{from: "work", from_address: "block:01a1ef15-4833-735e-9530-226d79648a16", instruction: "save", title_line: $t, context_line: $c}' \
      >"$STATE/queue/garden/$3.json"
  }
  bad $'- [ ] 🟢 **[a] b**\n## ✅ Done\n- [x] evil' '' 20990101-000000-000001
  bad "$TITLE" $'\tok\n## ✅ Done' 20990101-000000-000002
  bad 'Start a worker' '' 20990101-000000-000003
  bad "$TITLE" "$CONTEXT" 20990101-000000-000004
  rex_as_garden
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(jq -r .id <<<"$output")" = 20990101-000000-000004 ]
  [[ "$stderr" == *"20990101-000000-000001"* ]]
  run --separate-stderr bash "$SKILL_DIR/dispatch.sh" queue 20990101-000000-000002 "$O"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
