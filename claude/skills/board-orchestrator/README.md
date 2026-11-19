# board-orchestrator

The `/board-orchestrator <board>` skill runs one Kanban board of the vault. It dispatches
worker claudes for the cards and records their reports on the board. This README is for a
human. The agent reads `SKILL.md`, and `start.md`, `shorten.md` and `boards.md` when
`SKILL.md` sends it there.

## Files

| File | Use |
|---|---|
| `SKILL.md` | The rules of each turn. A compact reads it again (`hooks/compact.sh`). |
| `start.md` | Rules 1 to 4: the start of a session, the inbox, the resume of workers. |
| `shorten.md` | Rule 8: shorten the long cards. |
| `boards.md` | Send a card to the orchestrator of another board, and receive one. |
| `board-scan.sh` | Reads the board, the task notes, the project notes and the inbox. |
| `dispatch.sh` | Starts, lists and closes the workers, and writes reports, runs and logs. |
| `lib.sh` | Shared shell functions. |
| `term.sh` | The terminal functions for both backends. `lib.sh` sources it. |
| `board-watch.lua` | The board watcher of a Renux session. |
| `board.sh` | Lists the boards and the running orchestrators for the herdr-app mods board-open and board-stop. `claude-resume.sh` runs `board.sh restart` to start an orchestrator again in its shell after a reboot. |
| `hooks/compact.sh` | After a compact, tells the orchestrator to read `SKILL.md` again. |
| `hooks/guard.sh` | Blocks a `herdr-app do` call of a board worker, and a `rex` call that changes the window. A worker leaves the tabs as they are. Asks for a worker push with no review. |
| `test/*.bats` | The bats tests. `test/skill.bats` checks the skill text. |

## Workers

- In herdr-app, a worker is an `hc` terminal, a child of the orchestrator terminal. In Renux, see "Backends". It shows
  under the orchestrator in the agents list, and it ends when the orchestrator ends.
- A worker has an address such as `t7`. A Ctrl-click on the address peeks at the worker.
- A task worker gets the slug of its card: its branch, worktree and agent name. When 2
  card titles give the same slug, the second card gets the slug with `-2`.
- When `start` makes a new worktree and the repo has a make target `worktree-setup`, the
  worker terminal runs `worktree-setup.sh` before claude. It runs `make worktree-setup`
  in the start folder (else the worktree root) and keeps the output in a log beside the
  report. The prompt gives the worker that log. A worktree used again gets no setup.
- An automatic worker gets the allow rules of `<repo>/.claude/settings.readonly.json`,
  the allow rules and MCP servers of its board, the `hc send` rule and an edit rule for
  its report.
- Only one orchestrator of a board runs at a time. To restart, close the old orchestrator
  first (alt-shift-x). Each start is a new session that starts at rule 1.
- `SKILL.md` keeps `disable-model-invocation: true`. It stops worker claudes from loading
  the skill and its `Bash(dispatch.sh *)` permission. `test/skill.bats` checks it.

## Backends

The skill runs in herdr-app (`hc`) and in Renux (Rex). The backend of a terminal comes
from its address: `t7` is `hc`, and `block:…` or 8 hex digits is Rex. `BOARD_TERM` (`hc`
or `rex`) forces the backend of the caller. When it is not set, `HC_TERMINAL_ID` gives
`hc`, `REX_BLOCK` gives `rex`, and the default is `hc`. `term.sh` holds one `hc_` and one
`rex_` version of each terminal function.

| herdr-app (`hc`) | Renux (Rex) |
|---|---|
| Space "BOARD orchestrator" | Session "BOARD orchestrator" |
| Tab "orchestrator" | First tab of the session, label "orchestrator" |
| Worker: an `hc` child terminal | Worker: a tab of the board session, labeled with the worker name |
| Address `t7` | Block ID `block:…` (8 hex digits also work) |
| `HC_TERMINAL_ID` | `REX_BLOCK` and `REX_SESSION` |
| Labels on the terminal | A state file for each block |
| A child ends with its parent | `board.sh stop` closes the session, so its tabs close |
| Message `<hc from="t7 NAME">…</hc>` | Message `<rex from="SHORT NAME">…</rex>` |
| `hc read` | `rex capture`, or `dispatch.sh last` |
| `hc` tells blocked and exit | The board watcher |

- The orchestrator record keeps two columns, so the same file works for both backends.
- A worker reports with `dispatch.sh tell "report SLUG PATH"`. `tell` sends the text to the
  orchestrator in the right form for its backend.
- The watcher `board-watch.lua` starts with `board.sh open` and `board.sh restart`, with
  `rex do -s SESSION`. Rex does not tell the orchestrator that a worker is blocked or has
  exited, so the watcher does. It calls `dispatch.sh notice`, which sends
  `<rex>SHORT NAME is blocked (MSG). See: dispatch.sh last SHORT</rex>` or
  `<rex>SHORT NAME exited (exit CODE). See: dispatch.sh last SHORT</rex>`. These notices
  have no `from` attribute.
- In Renux, ctrl+b B opens a board, with one key for each board. ctrl+b X stops a board.
  When only one board runs, it stops at once. `board.sh running` lists only the boards of
  the backend of the caller, so a stop key never stops a board of the other app.
  `board.sh running all` lists the boards of both backends.
- `rex send` types raw text, and a newline submits the line. So a message with a newline
  goes to Rex as one bracketed paste, then Enter.
- The scripts call `rex` with `--autostart=false`: they never start a Rex server.
- After a Rex restart, `claude-resume.sh` runs `board.sh restart` for an orchestrator. It
  does not start the workers again.
- The Rex guard in `hooks/guard.sh` blocks the `rex` calls that change the window for a
  worker.

## Script output

### board-scan.sh

- `card BOARD TEXT`: one JSON line for each card in `📥 Backlog`, `📋 This Week`,
  `🔨 In Progress` and `⏳ Waiting On` whose title has TEXT (fixed text, any case). The
  keys: `column`, `line`, `checked`, `priority`, `recurring`, `date`, `due`, `title`,
  `owner`, `waits`, `links`, `context_long`, `title_line`, `context_line`, `task`,
  `task_exists` and `project`, also when null or false. With a task note, also `mode`,
  `recurrence` and `prompt`. `repo` is the `repo:` folder of the project note, or null.
  With a repo, also `policy` (`invalid` for a settings file that is not valid JSON) and
  `readonly` (the count of allow rules in `settings.readonly.json`).
  - `links`: the markdown links of the card with a scheme, with no worker address.
  - `context_long`: the context text has more than 200 characters, with no count for the
    tab and the `[[Tasks/...]]` and `[[Projects/...]]` links. The skill writes at most 180,
    so a new card does not come back at the next scan.
  - `context_line`: all the tab-indented lines after the title line, joined with a line
    end. It is empty for a card with none.
  - The last line:
    `{"done": N, "board": BOARD, "today": YYYY-MM-DD, "blank_after": {...}, "done_top": ..., "other": N, "projects": {...}}`.
    `blank_after` tells for each column if a blank line follows its heading. `done_top` is
    the top card of `✅ Done`, or null. `other` counts the cards under other headings.
    Only `cards` names those headings on stderr. Exit 2 is a board error.
- `cards BOARD`: the same lines with no card text, task path or repo, and with no null or
  false field. The Bash tool shows only 30 000 characters of an output.
- `prompt TASK`: the prompt block of a task note, with no fence lines. Exit 1: no prompt
  block. Exit 2: no note.
- `inbox`: one JSON line for each phone message in `_inbox`, oldest first: `file` (for
  example `_inbox/2026-11-04-173424.md`), `text` (cut at 2000 characters) and
  `truncated`. The last line is `{"inbox": N, "boards": {BOARD: [project notes]}}`.
- `rules`: the sections of the vault `_CLAUDE.md` on note frontmatter and on what not to touch.

### dispatch.sh

- `start task|auto CWD NAME PROMPT_FILE`: prints the worker address, then the report path.
  Exit 2: no worker. Exit 1: the git worktree or `hc` failed.
- `workers BOARD`: one JSON line for each running worker: `address`, `name`, `status`
  (working, blocked, idle or done), `mode`, `cwd`, `session`, `report`, `report_exists`,
  `first_line`, `report_mtime` and `waits`. `waits` is true for a blocked worker, and for
  an idle or done worker whose report is not `RESULT: DONE` or `STATUS: OK`. A worker that
  works never waits: its report is old.
- `resumable BOARD`: one JSON line for each worker that started and no longer runs (a
  stop, a closed space, a reboot): `session`, `mode`, `cwd`, `name`, `report`,
  `report_exists`, `first_line` and `done`. `resume` prints the address and the report
  path, and the old report path stays. `resume-clear` empties the list. A worker that
  the user opened in a tab is a kept terminal: after a reboot, hc puts a shell in the
  place of its claude, with the same labels. `workers` skips that shell, and
  `resumable` and `resume` close it (park, kill, rm), so no empty tab stays.
- `report REPORT`: the first line, the `## Result` section, the `## Vault changes`
  section, the `REFUSED:` lines, then `full report: REPORT (N lines)`. A report with no
  `## Result` gives its first 40 lines. A section over 60 lines is cut, with a
  `[section cut: N more lines]` line. The last line, `say:`, tells the orchestrator what
  to write to the user: a done line for the first `RESULT: DONE` or `STATUS: OK` of a
  report file (a file in the `said/` folder of the state folder keeps that), else
  `say: nothing.`.
- `run-add NOTE REPORT`: adds the report under `## Runs`, then `### YYYY-MM-DD`, demotes
  its headings by 3 levels, sets `updated:`, and replaces an entry of the same day. Exit
  2: usage. Exit 1: no vault or no note.
- `note-add NOTE BOARD LINE TITLE`: checks that the card is still at LINE, then copies its
  context text to the task note under `## Notes`.
- `policy CWD`: `deny`, `ask`, `allow`, `branch` or `missing`. `policy-set CWD allow|ask|branch` writes the
  push rules to `.claude/settings.local.json` of the project, and adds the merge rules to
  `permissions.deny`: `tea pr merge`, `tea pulls merge` and the Forgejo merge tool, and
  `gh pr merge` for an `origin` on `github.com`. For another `origin`, it writes the
  Forgejo rules and removes the `gh` rules that it wrote before. For `branch`,
  `hooks/guard.sh` decides each worker push. With each policy, the guard asks for a
  worker push when no `reviewer` agent started in the session after the oldest commit
  of the push. A squash with `git reset --soft` gives a new author date, and the push
  asks again.
  The prompt of a task worker gives the policy of its card repo, and a push rule in the
  `CLAUDE.md` of that repo comes first.
- `last ADDRESS`: the last assistant message of the worker (at most 3000 characters), else
  the last 40 lines of its screen. Exit 1: the worker is gone.
- `remind ADDRESS REPORT`: asks an idle or done worker to write its report again. Exit 1:
  the worker is gone or works.
- `answer ADDRESS FILE`: sends FILE after the line "The user answers through the
  orchestrator:", only to an idle or done worker. Exit 1: gone, works or blocked. Exit 2:
  FILE missing or empty.
- `close ADDRESS [wait]`: waits up to 90 seconds for the end of the turn (no limit with
  `wait`), ends the worker and prints its session ID, or an empty line. The report stays.
  Exit 1 with "no agent": not a worker. Exit 1 with "still working": it closed nothing.
- `log BOARD FILE`: adds one line to `Dev Logs/YYYY-MM-DD - BOARD (board orchestrator).md`
  and a link to it in the daily note.
- `inbox-clear FILE`: deletes one `_inbox/<name>.md` file. Exit 2: another path. Exit 1:
  the file is gone (the orchestrator of another board took it).
- `send BOARD start|save FILE`: writes the card of FILE and the instruction to
  `queue/<board slug>/<id>.json` in the state folder, then sends `card <id>` to the
  orchestrator of BOARD when it runs. The card stays in the queue until that orchestrator
  adds it. Exit 2: the own board (by slug), no such board file, or FILE is not one open
  card (a title line, then only tab-indented lines, at most 2000 bytes).
- `queue [ID FROM]`: the cards in the queue of the caller board. `live` is true only when
  FROM is the live orchestrator that sent the card: only then a `start` card starts a
  worker with no question. A file that is not one open card is skipped. Exit 1: gone.
- `queue-clear ID`: deletes one card of the queue. Exit 1: gone. Exit 2: not a queue ID.

## Why the rules are so

- A card move inserts first, then removes. A failure leaves a duplicate card, never a lost
  card.
- `obsidian_replace_text` fails when the user edits the board at the same time. It does
  not overwrite the edit.
- `obsidian_read_note` returns at most 20 000 characters. A task note keeps all runs under
  `## Runs`, so it grows with each run.
- The worker lines of the task list start at the left edge, with no bullet: the terminal
  shows a nested number as a letter ("ai." for 35).
- A subagent gets rule 8 unchanged: on 2026-11-05, a subagent prompt with a changed rule
  dropped the `[[Projects/...]]` link of 9 open cards.
- `/obsidian-board` has its own column rules, so the orchestrator does not use it.

## Tests

`bats claude/skills/board-orchestrator/test`. `test/skill.bats` checks the rule numbers of
each part, the commands that the skill names, and a cap of 33 000 bytes on `SKILL.md`.
