# Board orchestrator: start of a session

This part of the board-orchestrator skill gives rules 1 to 4. `SKILL.md` gives what you
write, the tools, the output of `card`, the "New card" steps and the rules 5 to 8. All its
rules apply here. Rule 9 is in `~/.claude/skills/board-orchestrator/shorten.md`.

These commands are only in this part. Run them in this form only, with `bash`:

```bash
bash ~/.claude/skills/board-orchestrator/board-scan.sh cards BOARD
bash ~/.claude/skills/board-orchestrator/board-scan.sh prompt TASK
bash ~/.claude/skills/board-orchestrator/board-scan.sh inbox
bash ~/.claude/skills/board-orchestrator/dispatch.sh inbox-clear FILE
bash ~/.claude/skills/board-orchestrator/dispatch.sh resumable BOARD
bash ~/.claude/skills/board-orchestrator/dispatch.sh resume BOARD SESSION
bash ~/.claude/skills/board-orchestrator/dispatch.sh resume-clear BOARD [SESSION]
```

`board-scan.sh cards BOARD` prints one JSON line for each card in `📥 Backlog`,
`📋 This Week`, `🔨 In Progress` and `⏳ Waiting On`, with the fields of `card` (see
`SKILL.md`), but with no card text, no task path and no repo: no `title_line`,
`context_line`, `task`, `task_exists`, `repo`, `policy` and `readonly`. The Bash tool
shows only 30000 characters of an output. Get them from `card`. A field that is null or
false is not in the line: a card with no `due` field is not due. The last line is the
last line of `card`. The `repo`, `policy` and `readonly` of a card are those of its
`project` in `projects`. A card with no `project` has no repo.

`board-scan.sh prompt TASK` prints the text of the prompt block of a task note, with no
fence lines. TASK is the `task` field of `card`, for example `Tasks/X.md`. Put TASK in
single quotes. It exits 1 when the note has no prompt block, and 2 when the note does not
exist.

`board-scan.sh inbox` prints one JSON line for each phone message in the vault folder
`_inbox`, oldest first: `file` (relative to the vault, for example
`_inbox/2026-11-04-173424.md`, the date and time of the message), `text` (cut at 2000
characters) and `truncated`. The last line is
`{"inbox": N, "boards": {BOARD: [project notes]}}`: the project notes that the cards of
each board link to, for example `"garden": ["Projects/dotfiles", ...]`.
`dispatch.sh inbox-clear FILE` deletes one message file. FILE is the `file` field. It
accepts only `_inbox/<name>.md`, and exits 2 for another path. It exits 1 when the file
is gone (the orchestrator of another board made a card of it first) and prints
`inbox-clear: FILE` on success.

`resumable` prints one JSON line for each worker of the board that started and no longer
runs (a stop, a closed space, a reboot): `session`, `mode`, `cwd`, `name`, `report`,
`report_exists`, `first_line` and `done`.

## Rules 1 to 4

1. **Read.** Run `bash ~/.claude/skills/board-orchestrator/board-scan.sh rules` and follow
   those rules when you write a task note: keep the frontmatter. `obsidian_update_note`
   sets `updated:` itself. Then run
   `bash ~/.claude/skills/board-orchestrator/board-scan.sh cards BOARD`. It gives each card
   with its task note fields, and on the last line the repo, push policy and read-only
   rule count of each project (`projects`). Do not read the
   board, the task notes or the project notes one by one for this. Read a task note with
   the vault MCP tool only when the user asks. To get the prompt block of a card,
   run `board-scan.sh prompt '<task>'` (`task` of `board-scan.sh card`). To record a run (rule 7.3), do not read the note: `dispatch.sh run-add`
   does the edit. The worker folder is the `repo` of the card project in `projects`. Then run
   `bash ~/.claude/skills/board-orchestrator/board-scan.sh inbox` for the inbox of rule 4.
   To refresh the full state (for example when the user asks), run
   `board-scan.sh cards BOARD` again. Before a record, run `board-scan.sh card` (rule 7).
   Then adopt the running workers: run
   `bash ~/.claude/skills/board-orchestrator/dispatch.sh workers BOARD`. For each line,
   find its card. The agent name comes from the card title: match on `name`. When no
   card matches, match on the report text. When nothing matches, ask the user. Then:
   - `report_exists` false: do nothing. The report comes as a message (rule 6).
   - The report exists, and the card already shows that result (its column and the
     `context_line` of `board-scan.sh card BOARD '<title>'` agree with `first_line`): do
     nothing.
   - The report exists, and the card does not show it: record it with rule 7, as a new
     result.
   - `report` null: tell the user the address and the name.
   Then tell the user one line for each worker: the card, the status and the
   address. When the output is empty, say "No running worker".
   In that line, say "waits for you" only when `waits` is true.
   Then run `bash ~/.claude/skills/board-orchestrator/dispatch.sh resumable <board>`.
   A stop of the orchestrator closed these workers and kept their session IDs. The output
   has one JSON line for each closed worker, with `session`, `mode`, `cwd`, `name`,
   `report`, `report_exists`, `first_line` and `done`. With no output, do nothing more here.
   - Find the card of each line as the adopt step does: match on `name`, then on the
     report text. When nothing matches, ask the user.
   - For a line with `done` true: record the report on its card as rule 7 does for a done
     result. Put "session `<id>`" on the context line, as rule 7.8 does. When the card
     shows that result already with the old worker address, replace only the address
     with "session `<id>`". Offer no resume and run no `close`, because the worker is
     closed already.
   - For each line with `report_exists` true: compare its card with the report, as the
     adopt step does (the column and the `context_line` of
     `board-scan.sh card BOARD '<title>'` agree with `first_line`). When the card does
     not show the report, record it with rule 7 first, as a new result, and run no
     `close`. The `done` bullet above uses the same check, so a result is not recorded
     twice. A line that is not `done` still gets the question after its record.
   - For the other lines: ask one "I ask:" question. List each worker with its card title.
     Ask which workers to resume.
   - For each worker that the user picks: run
     `bash ~/.claude/skills/board-orchestrator/dispatch.sh resume <board> <session>`.
     It prints the address, then the report path. The old report path stays. The next
     report of the worker comes as a message (rule 6).
   - When `resume` exits 1 or 2, tell the user the stderr text and put "session `<id>`"
     on the card. Never run `start` for it.
   - For each worker that the user does not pick: put "session `<id>`" on its card
     context line.
   - Then run `bash ~/.claude/skills/board-orchestrator/dispatch.sh resume-clear <board>`,
     also when the user picks no worker.
   Two orchestrators of one board must not run at the same time. To restart, the user
   closes the old orchestrator first (alt-shift-x). Each start of the orchestrator is a
   new session that starts at rule 1.
   Never dispatch a card (rules 3 and 5) whose worker you adopted here: that worker
   still runs. Also do not dispatch (rules 3 and 5) or list (rule 4) the card of a line of
   `resumable` before the user answers. A resumed worker is the worker of its card, as an
   adopted worker is.
2. **Classify** with the scan fields. An open card has no `checked` field. A card is
   automatic when its `mode` is `auto`. All other open cards are board tasks. A card is
   due when `due` is true. Skip these cards. Do not dispatch them. Only list them for the
   user:
   - cards with a `waits` value, whatever name it holds,
   - cards with an `owner` value that is a person, not Claude,
   - cards with `column` `⏳ Waiting On`, and the `done` count of the last line.
3. **Dispatch the due automatic tasks at once**, before you talk with the user. Do not ask
   for approval. For each task:
   1. Write the prompt file to your scratchpad. Run `board-scan.sh card BOARD '<title>'`
      for the `task` path. When `prompt` of the scan is true, run
      `bash ~/.claude/skills/board-orchestrator/board-scan.sh prompt '<task>'`. The prompt
      is its output. Do not read the task note with the vault MCP tool. When the note has
      no prompt block (exit 1), the prompt is the card text (`title_line` and
      `context_line` of `card`) and the task note path, with the instruction to read the
      task note.
   2. Run `bash ~/.claude/skills/board-orchestrator/dispatch.sh start auto <repo> '<name>' <prompt file>`.
      The worker gets only the rules of `<repo>/.claude/settings.readonly.json`.
   3. When the card project in `projects` has no `repo`, do not dispatch it. The task is a
      board task. When the `readonly` of that project is 0, do not dispatch it: the task
      is a board task. Tell the user that
      the project has no read-only list.
   4. Exit 2 with a `settings.readonly.json` message on stderr (the file is missing, is not valid
      JSON, or has no allow rule): the task is a board task. Tell the user that the project
      has no read-only list. Exit 2 for another cause: tell the user the stderr text, and
      do not change the card. Exit 1: follow rule 5.4 for exit 1.
4. **Talk.** Show the user the due board tasks in a short numbered list. Number them 1,
   2, 3 and on, with no gap. Do not use the `line` or the place of a card on the board
   as its number. Write one line for each task, in this form:
   `1. 🟡 [<project>] <title> — [<repo>](file://<repo>) <links>`
   Start each line at the left edge with its number. Put no "-" bullet, no indent and
   no blank line before or between the lines. The terminal shows a number in a nested
   list as a letter ("ai." for 35), and the user cannot answer with it.
   The worker folder is the `repo` of the card project in `projects`, as an absolute
   path. `<links>` are the `links` of the card, as they are, or nothing. Ask which tasks
   to dispatch. When a card has no repo, write "no folder" in place of the link, and
   ask the user for the folder. Then show the skipped cards in one short list, one line
   for each card, in this form: `- [<project>] <title> — <why it waits> <links>`.

   **Inbox.** Then show the phone messages of `board-scan.sh inbox` in 2 lists. Number
   them after the due board tasks, so that one answer covers both. One line for each
   message: the date and time of its file name, its text on one line (at most 100
   characters), and for the first list the project.
   - "Inbox for this board": the messages about a project in `boards[BOARD]`.
   - "Inbox, no board": the messages that match no board, or more than one board, or
     when you are not sure.
   Do not show a message about a project of another board only: the orchestrator of
   that board shows it. Write no list when it is empty. Ask what to do with each message:
   add, start, put on another board or project, or skip. A message with no answer is a
   skip. For each message to add, start or put elsewhere:
   1. Write the card with step 1 of "New card" (`SKILL.md`). The title is a short action
      from the message.
   2. Show the card to the user with "I ask:", and add it only when the user approves.
   3. Check and insert the card with step 2 of "New card".
   4. Only after the insert worked, run
      `bash ~/.claude/skills/board-orchestrator/dispatch.sh inbox-clear <file>`. When it
      fails, tell the user the stderr text in one line. On a failed insert, run no
      `inbox-clear`: the message stays in the inbox.
   5. Tell the user "I added the task <title>." with the board, and log it (rule 7.10).
   6. For "start", dispatch the new card with rule 5 in the same turn. The "start" of the
      user is the yes for the worker: do not ask "start a worker?" again. Start a worker
      only for a card of this board. For a card on another board, tell the user that the
      orchestrator of that board starts it.

   After the lists and your question, in the same turn, shorten the long cards (rule 9).
