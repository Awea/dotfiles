# Board orchestrator: start of a session

This part of the board-orchestrator skill gives rules 1 to 4. All the rules of `SKILL.md`
apply here.

These commands are only in this part. Run them in this form only:

```bash
bash ~/.claude/skills/board-orchestrator/board-scan.sh cards BOARD
bash ~/.claude/skills/board-orchestrator/board-scan.sh prompt TASK
bash ~/.claude/skills/board-orchestrator/board-scan.sh inbox
bash ~/.claude/skills/board-orchestrator/dispatch.sh inbox-clear FILE
bash ~/.claude/skills/board-orchestrator/board-scan.sh multica BOARD
bash ~/.claude/skills/board-orchestrator/dispatch.sh multica-done BOARD ID
bash ~/.claude/skills/board-orchestrator/dispatch.sh queue
bash ~/.claude/skills/board-orchestrator/dispatch.sh resumable BOARD
bash ~/.claude/skills/board-orchestrator/dispatch.sh resume BOARD SESSION
bash ~/.claude/skills/board-orchestrator/dispatch.sh resume-clear BOARD [SESSION]
bash ~/.claude/skills/board-orchestrator/dispatch.sh triage-check BOARD
```

`cards` gives the lines of `card` for the full board, with no card text and no task path:
get those from `card`. A field that is null or false is not in a line. The `repo`,
`policy` and `readonly` of a card are those of its `project` in `projects` of the last
line. A card with no `project` has no repo.

## Rules 1 to 4

1. **Read, adopt and resume.** Do the three steps in this order.
   a. **Read.** Run `board-scan.sh rules`, and keep the frontmatter when you write a task
      note. Run `board-scan.sh cards BOARD` for the cards, and `board-scan.sh inbox` for
      the inbox of rule 4. These two give all that rules 1 to 4 need: read no board,
      task note or project note one by one. Run `board-scan.sh multica BOARD` for the
      Multica list of rule 4. Run `cards` again to refresh the state.
      When `other` of the last `cards` line is more than 0, tell the user the headings
      that stderr names.
      Run `dispatch.sh queue` for the cards that other boards sent. When it prints a
      line, read `~/.claude/skills/board-orchestrator/boards.md` and add the cards as its
      last section tells. Start no worker for them here.
      Run `dispatch.sh triage-check BOARD`. On a `due` line, read
      `~/.claude/skills/board-orchestrator/triage.md`: rule 4 asks its T1 question.
      Done: you have the `rules`, `cards`, `inbox`, `queue` and `triage-check` output, and
      each `queue` card is on the board.
   b. **Adopt the running workers.** Run `dispatch.sh workers BOARD`. A line with `mode`
      `triage` has no card: follow T4 of `triage.md` for it. Find the card of each other
      line: match `name` on the card title, then on the report text. When nothing
      matches, ask the user. Then:
      - `report_exists` false: do nothing. The report comes as a message (rule 6).
      - The card shows the report (its column and the `context_line` of `card` agree with
        `first_line`): do nothing.
      - The card does not show the report: record it with rule 7, as a new result.
      - `report` null: tell the user the address and the name.
      Tell the user one line for each worker: the card, the status and the address ("Waits
      for you" in `SKILL.md`), or "No running worker".
      Done: each line of `workers` has its card or a question, and the user has the
      worker lines.
   c. **Resume the closed workers.** Run `dispatch.sh resumable BOARD`: one line for each
      worker that a stop of the orchestrator or a reboot closed. With no output, this step
      is done.
      - Find the card of each line as step 1b does. A line with `mode` `triage` has no
        card: follow T4 of `triage.md` for it.
      - A line with `report_exists` true: when the card does not show the report (the
        check of step 1b), record it with rule 7 first, as a new result. Run no `close`:
        the worker is closed already.
      - A line with `done` true: put "session `<id>`" on the context line in place of the
        worker address, as rule 7.8 does. Offer no resume.
      - For the lines that are not `done`, ask one "I ask:" question: which workers to
        resume, each with its card title.
      - Each worker that the user picks: run `dispatch.sh resume BOARD <session>`. Its
        next report comes as a message (rule 6). On a nonzero exit, put "session `<id>`"
        on the card, and never run `start` for it.
      - Each worker that the user does not pick: put "session `<id>`" on its card.
      - Then run `dispatch.sh resume-clear BOARD`, also when the user picks no worker.
        Tell the user each stderr line `dispatch: kept the worktree ...` as it is.
      Done: `resumable` printed nothing, or `resume-clear` ran and each card of a closed
      worker has its address, a resume or "session `<id>`".
   Dispatch no card whose worker you adopted or resumed: that worker still runs. Until the
   user answers, also dispatch and list no card of a `resumable` line.
2. **Classify** with the scan fields. An open card has no `checked` field. A card with
   `mode` `auto` is automatic. All other open cards are board tasks. A card with `due`
   true is due. List these cards for the user, and dispatch none of them:
   - cards with a `waits` value, whatever name it holds,
   - cards with an `owner` value that is a person, not Claude,
   - cards in `⏳ Waiting On`, and the `done` count of the last line.
3. **Dispatch the due automatic tasks at once**, before you talk with the user, with no
   approval. For each task:
   1. A card project with no `repo`, or with `readonly` 0, makes the card a board task:
      skip steps 2 to 4 for it. For `readonly` 0, tell the user that the project has no
      read-only list.
   2. Write the prompt file to your scratchpad. When `prompt` of the `card` line is true,
      the prompt is the output of `board-scan.sh prompt '<task>'`. Else it is the card
      text, the task note path and the instruction to read the task note.
   3. Run `dispatch.sh start auto <repo> '<name>' <prompt file>`. The worker gets the
      allow rules of `<repo>/.claude/settings.readonly.json` and of its board.
   4. Exit 2 with a `settings.readonly.json` message on stderr: the card is a board task.
      Tell the user that the project has no read-only list. For each other nonzero exit,
      change nothing on the card (rule 5.4).
4. **Talk.** Show the due board tasks in a numbered list: 1, 2, 3 and on, with no gap, one
   line for each task, in this form:
   `1. 🟡 [<project>] <title> — [<repo>](file://<repo>) <links>`
   Start each line at the left edge, with no bullet, no indent and no blank line between
   the lines: the terminal shows a nested number as a letter ("ai." for 35). `<repo>` is
   the absolute path of the card project, and `<links>` are the `links` of the card. For
   a card with no repo, write "no folder" and ask for the folder. Ask which tasks to
   dispatch. Then show the skipped cards of rule 2, one line for each:
   `- [<project>] <title> — <why it waits> <links>`.
   A card with a `multica` field is with a Multica agent: it is not a due board task.
   Show it with the skipped cards, why it waits: `with a Multica agent (<multica>)`.
   A card that you added from `queue` in rule 1a is a due board task, once in the list.
   When its `instruction` is `start`, add `— from <from>, to start` at the end of its
   line. Dispatch it only when the user picks it.

   **Inbox.** Then show the inbox messages in 2 lists, numbered after the board tasks, so
   that one answer covers all. One line for each message: the date and time of its file
   name, its text on one line (at most 100 characters), and in the first list the
   project.
   - "Inbox for this board": the messages about a project in `boards[BOARD]` of the last
     inbox line.
   - "Inbox, no board": the messages that match no board, more than one board, or when
     you are not sure.
   Leave out a message about a project of another board only: its orchestrator shows it.
   Write no empty list. Ask what to do with each message: add, start, put on another
   board or project, or skip. No answer is a skip. For a message that the user puts on
   another board, send the card with `~/.claude/skills/board-orchestrator/boards.md`:
   "add" is `save`, "start" is `start`. For each other message to add, start or put on
   another project:
   1. Write the card with step 1 of "New card". The title is a short action from the
      message.
   2. Show the card with "I ask:", and add it only when the user approves.
   3. Check and insert the card with step 2 of "New card".
   4. After the insert worked, run `dispatch.sh inbox-clear <file>`. After a failed
      insert, keep the message in the inbox.
   5. Tell the user "I added the task <title>." with the board, and log it (rule 7.10).
   6. For "start", dispatch the card with rule 5 in the same turn: "start" is the yes for
      the worker.

   **Multica.** Then show the open items of `board-scan.sh multica BOARD` in a third list,
   "Multica", numbered after the inbox lists. One line for each item:
   `<n>. <key> <title> — <edit>`. Write no empty list. The items come from
   `multica-perso export`, which the user runs. Ask which items to apply. No answer is a
   skip, and a skipped item stays open. For each approved item:
   1. Find the card with `board-scan.sh card BOARD '<title>'`, except for `new-card`.
      When no card or more than one card agrees, tell the user and change nothing for
      that item.
   2. Apply the edit with the normal rules of rule 7: `move to <column>` moves the card
      ("Move a card"), `context: <text>` writes the context line ("Context line"), and
      `move to ✅ Done` also marks it done (rule 7.4). For `new-card`, write the card
      with the "New card" steps, with the title of the item and `in Multica <key>` on
      its context line.
   3. After the edit worked, run `dispatch.sh multica-done BOARD <id>`.
   4. Log it (rule 7.10).

   After the lists, when `triage-check` printed `due`, ask the T1 question of `triage.md`.
   After the lists and your questions, in the same turn, shorten the long cards (rule 8).
