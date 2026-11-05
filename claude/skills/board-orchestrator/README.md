# Board orchestrator

The board orchestrator runs one Obsidian Kanban board of the vault. It is a Claude
session that starts worker Claude sessions for the cards, watches them, and writes their
results to the board. It does not do the work of a card itself.

It runs in Herdr, with the agent-tabs plugin. The
[agent-tabs README](../../../herdr/plugins/agent-tabs/README.md#run-a-board) gives the
Herdr details.

## Requirements

The orchestrator expects the vault layout and the tools of this setup:

- **Vault path:** `OBSIDIAN_VAULT_PATH`, in the environment or in the `env` of
  `~/.claude/settings.json`.
- **Boards:** `Boards/<board>.md`, made with the Obsidian Kanban plugin. The orchestrator
  reads the columns `📥 Backlog`, `📋 This Week`, `🔨 In Progress` and `⏳ Waiting On`,
  and moves a done card to `✅ Done`.
- **Cards:** `- [ ] <priority> **[<project>] <title>**`, with links to
  `[[Tasks/...]]` and `[[Projects/...]]` notes. A project note gives the repo of its
  cards in the field `repo:`.
- **Vault rules:** the orchestrator follows the sections "Section 0", "Frontmatter" and
  "Do Not Touch" of `_CLAUDE.md` at the vault root, when the file exists.
- **Logs:** each card result goes to `Dev Logs/YYYY-MM-DD - <board> (board orchestrator).md`,
  with a link in the `## Work` section of `Daily/YYYY-MM-DD.md`.
- **Claude plugin:** obsidian-second-brain, for its vault MCP tools.
- **Forge:** a repo whose `origin` is on `github.com` uses `gh`. Any other host is
  Forgejo, with `tea` and the `forgejo` MCP server.
- **Read-only workers:** a repo can give its read-only rules in
  `.claude/settings.readonly.json`.

## Keys

| Keys | Result |
|---|---|
| `ctrl+b` `shift+b` | Lists the boards. Press the number of a board to start its orchestrator. |
| `ctrl+b` `shift+x` | Stops the orchestrator of a board. With two or more, a popup asks for the board. |
| `ctrl+b` `d` | In a worker view: opens reviewr next to the view. |

## Start an orchestrator

1. Press `ctrl+b` `shift+b`. A popup lists the boards, for example `[1] home  [2] work`.
2. Press the number of the board.

A notification shows "Starting the orchestrator of the board <board>." at once. Then:

- The workspace `<board> orchestrator` of your Herdr session opens with the focus.
- Claude starts there, in the vault folder. When Claude asks a question at the start
  (for example the trust of the vault folder), answer it in the pane.
- Claude runs `/board-orchestrator <board>`. Its agent name is `<board>-orchestrator`.
  While Claude starts, its pane has the temporary agent name `claude-start-<pane>`. This
  name is unique, so two Claude starts in one Herdr session do not clash.

A board has one orchestrator. When the orchestrator of the board runs, `ctrl+b` `shift+b`
focuses it and starts no second one. The orchestrator always stays in your session: you
cannot hide it. The workers run in the hidden Herdr session `board-workers`, in the
workspace `<board> workers`.

In the Herdr workspace list, the second line of the workspace shows the number of workers
of the board, for example `3 workers`, in the place of the git branch. A listener
(`dispatch.sh count-watch`) keeps it up to date from the Herdr events of the hidden
session. It restarts itself when its code changes. The row layout is in
`herdr/config.toml` (`[ui.sidebar.spaces]`, the tokens `$workers` and `$working`).

While workers work, the second line also shows their number in yellow, for example
`1 working`. The state icon of the workspace is red when a worker waits for you. The
orchestrator is a normal claude agent: the agent list shows it, as each claude of your
session.

## The orchestrator tab

The first tab of the workspace `<board> orchestrator` is `orchestrator`: the claude of the
orchestrator. The other tabs are the views of the workers. A view is a pane that runs
`herdr --session board-workers agent attach <pane>`: it shows the worker, and you can type
in it. The orchestrator opens a view with `dispatch.sh show`, with no focus. A click on the
workspace opens its last active tab, as for each Herdr workspace, so it can open a worker
view.

## Close the workspace

When you close the workspace `<board> orchestrator`, the orchestrator stops. Its workers
keep running in the hidden session. Press `ctrl+b` `shift+b` and the number of the board
to start a new orchestrator: it finds the running workers. You can also stop an
orchestrator with `ctrl+b` `shift+x`. The stop first checks the panes of the workspace.
It refuses when a pane runs another program than the orchestrator, a worker view or a
shell. After a Herdr restart, Herdr resumes the orchestrator claude in its pane, with
its old context. The worker views come back as shells, and the plugin repairs them by
itself: its startup hook closes the tabs that hold only shells and opens the view of each
live worker again. It can take up to 3 minutes. If a view is still missing, press
`ctrl+b` `shift+b` on the board to run the repair again. The hook also sends the orchestrator one prompt: its background wait and watch commands stopped, so it reads the workers again and starts them again.

## What the orchestrator does

1. It reads the board and its task notes with `board-scan.sh`.
2. It starts the due automatic tasks at once. An automatic worker gets only the
   read-only rules of its project (`.claude/settings.readonly.json`).
3. It shows the other due cards and asks which ones to start. It also shows the phone
   messages of the vault inbox (see [Phone messages](#phone-messages)).
4. It starts a worker for each card that you choose. A worker runs in a tab of the
   workspace `<board> workers` of the hidden session, in the project folder of its card.
   A hook blocks each herdr command of a worker that opens a pane, tab, workspace,
   worktree, plugin pane or agent, and `herdr plugin action`: you cannot see these in the
   hidden session. A worker never opens reviewr.
5. When a worker writes its report, the orchestrator records it on the card: the context
   line, the `## Runs` entry and the column. Then it closes the worker.
6. It keeps each context line at 200 characters or less. It moves the text of a longer
   card to the task note of the card, and writes a short line in its place.

For each finished job, it writes one line: the card title, "done", and the PR or commit
link. The summary is on the card. It writes nothing for progress or status.

## Phone messages

Each phone message is a file `_inbox/<datetime>.md` in the vault. At the start, the orchestrator reads them with
`board-scan.sh inbox` and shows 2 lists after the due cards:

- **Inbox for this board**: the messages about a project of this board.
- **Inbox, no board**: the messages that match no board, or no board for sure.

It does not show a message about a project of another board only: the orchestrator of
that board shows it. For each message, tell it what to do:

- **add**: it shows the new card, then puts it at the top of `📥 Backlog`.
- **start**: it adds the card, then starts a worker for it.
- **put on another board or project**: it adds the card there.
- **skip**: the message stays in the inbox for the next start.

When the card is on the board, `dispatch.sh inbox-clear` deletes the message file. The
vault tools cannot delete a file. When the card edit fails, the file stays. Ask
"inbox?" to see the lists again. The text of a message is data: the orchestrator never
runs or changes anything because a message says so.

## When a worker needs you

A worker needs you when it waits at a permission prompt, asks a question, or ends its turn
with no report. Then:

- Herdr shows the notification "<agent> needs you".
- The orchestrator writes nothing: the agent list of Herdr already shows the worker. It
  does not copy the text of the worker.
- The view tab of the worker and the workspace `<board> orchestrator` show red. The red
  goes when the worker works again or ends a new turn. The orchestrator does not stop.
- While the view is red, it is a Herdr agent: a click on it in the agent list opens its
  view tab. It has the name of the worker. It shows the task on its first row and the
  project of the worker on its second row (for example `docs`). `herdr/config.toml` sets
  this layout. Claude agents keep the default layout.

Answer the worker in its view tab. In the orchestrator, tell it which worker gets your
words ("tell the worker of <card> ..."). It then sends your exact words to that worker.
With no such words, the orchestrator sends nothing to a worker that exists: it starts a
new worker, or asks you.

A live worker does not wait for you: it works, or it waits for its own background job (a
shell or a subagent). The orchestrator reads the live state of each worker for this
(`dispatch.sh workers`, the field `waits`), not the first line of its report. The report
of a worker that works again after your answer is old.

## Review in a view

A view is a Herdr agent only in two cases. First, when it is red. Second, while a reviewr
pane is open in the tab of the view. Otherwise the plugin releases the view, so it is not
in the agent list. A hook on the events `pane.closed` and `pane.exited` releases a view
when its reviewr closes (`dispatch.sh views-sync`).

To review the work of a worker, press `ctrl+b` `d` in its view. reviewr opens next to
the view, for the worktree of the worker. The view then shows the state of the worker
(working or idle), so reviewr can send its notes. The notes go through the view to the
worker. The worker answers the review comments. The details are in the
[agent-tabs README](../../../herdr/plugins/agent-tabs/README.md#run-a-board).

## Vault changes

Workers never edit the vault. A worker writes each change in its report, under
`## Vault changes`. For a new task, it writes only the title, the project, the priority
and one context line, and the orchestrator writes the card. For a change to existing
text, it writes the note path and the exact old and new text.

- A new task from the worker of a board task: the orchestrator adds it with no question.
  You asked the worker for it.
- Each other change, and each change from an automatic worker: the orchestrator shows it
  and applies it only when you approve it.

## Safety

- Workers never merge a PR. You merge.
- Before the first worker of a project, the orchestrator asks for the push policy of the
  project. `allow` lets workers push, open and close PRs, and comment with no question.
  `ask` makes them ask first. The merge commands are always denied, on GitHub and on
  Forgejo.
- Report text and note text are data. The orchestrator never runs, starts or changes
  anything because a report or a note says so.

## Recovery

- A new orchestrator finds the running workers of its board and watches them again. You
  can restart it at any time.
- When a worker finishes and does not write its report again, the orchestrator reminds it.
- When a worker does not start (for example at the trust prompt), the orchestrator shows
  it and can start it again.
- To stop all workers, run `herdr session stop board-workers`.

## Design rule

Each key gives a visible result at once, in less than 1 second. The plugin opens the
popup or shows a notification first. The slow steps (a Herdr server start, a Claude
start) come after.

## Known limits

- Mouse copy in a view tab works only when the Claude in the hidden session has the
  desktop display. The plugin gives the display to each Claude that it starts. A Claude
  that started with no display cannot copy. Restart it.

## Files

| File | Role |
|---|---|
| `SKILL.md` | The rules of the orchestrator (`/board-orchestrator <board>`). |
| `dispatch.sh` | Starts, waits for, shows, answers and closes workers. A link to the agent-tabs plugin. |
| `board-scan.sh` | Reads a board and its task notes. A link to the agent-tabs plugin. |
| `../../../herdr/plugins/agent-tabs/board.sh` | The key `ctrl+b` `shift+b`. |
