# agent-tabs

A local Herdr plugin that opens claude, or a shell in the main git worktree, in a new tab.
Claude starts a conversation with your prompt, or it continues the focused conversation
with a `/handoff` document.

The plugin also gives each claude in Herdr its session title as agent name, and changes
the name after `/rename`. The shortcut `ctrl+b` `d` opens reviewr next to claude.

## Shortcuts

The prefix is the Herdr default, `ctrl+b`.

| Keys | Action | Result |
|---|---|---|
| `ctrl+b` `a` | `awea.agent-tabs.new-tab` | Asks for a prompt, an effort level and the tab focus, then starts claude with them in a new tab. In a linked git worktree, claude starts in the root of the main worktree of the repo. Else, claude starts in the folder of the focused pane. The tab opens in the background by default. The sidebar shows the session title of claude as the agent name. An empty prompt opens a clean claude tab. |
| `ctrl+b` `shift+a` | `awea.agent-tabs.handoff` | Moves the focused claude conversation to a new tab with `/handoff`. |
| `ctrl+b` `shift+b` | `awea.agent-tabs.board` | Lists the Kanban boards of the vault. After you press the number of a board, the workspace `<board> orchestrator` opens with the focus. An orchestrator claude starts there, in the vault folder, and runs `/board-orchestrator <board>`. |
| `ctrl+b` `shift+x` | `awea.agent-tabs.board-stop` | Stops a board orchestrator: closes its workspace `<board> orchestrator`. The workers go on. With two or more orchestrators, a popup asks for the board. |
| `ctrl+b` `c` | `awea.agent-tabs.new-shell-tab` | Opens a shell tab without claude and gives it the focus. The tab starts in the same folder as the `ctrl+b` `a` tab. |
| `ctrl+b` `d` | `awea.agent-tabs.reviewr` | Opens reviewr right of the focused pane, for the git worktree of the most recent work of claude in that pane. reviewr shows the last claude turn and diffs against the target branch of the pull request. |

The key bindings are in `herdr/config.toml`.

## Start a conversation

1. Focus a pane in the workspace and folder that you want.
2. Press `ctrl+b` `a`. A popup opens.
3. Type the prompt and press Enter.
4. Press one key for the effort: `l` low, `m` medium, `h` high, `x` xhigh, `M` max.
   To keep the claude default, press Enter.
5. To give the focus to the new tab, press `y`. To keep the focus on your pane, press
   `n` or Enter.

The new tab opens, and claude starts with your prompt and effort. To cancel in the
popup, press Esc or `ctrl+c`.

If the pane is in a linked git worktree, claude starts in the root of the main worktree
of the same repo. A pane in a subfolder of the linked worktree also gives the main root.
In all other cases, claude starts in the folder of the focused pane. This includes a
pane in the main worktree, a pane outside a git repo and a bare repo. The handoff does
not do this. Its new tab stays in the folder of the old claude.

The prompt line uses readline, so the shell keys edit the text. For example, `ctrl+w`
and `alt+backspace` delete a word, `ctrl+u` deletes the line, and the arrow keys move
the cursor. A newline in a pasted text becomes a space, so only Enter sends the prompt.
The focus line of the handoff popup uses the same keys.

Claude gives the session a title after the first prompt. The plugin uses this title as the
agent name in the sidebar, as a slug of 30 characters or less. If claude gives no title in 60 seconds,
the agent gets the start of your prompt. Agent names must be unique, so the plugin adds
a number to a name that is taken, for example `postgres-port-issue-2`.

To start a clean conversation, press Enter on an empty line in step 3. Claude in the new
tab is ready for your prompt. To type the prompt at once, press `y` in step 5.

## Run a board

The [board orchestrator README](../../../claude/skills/board-orchestrator/README.md) gives
all features of the orchestrator. This section gives the keys and the Herdr details.

1. Press `ctrl+b` `shift+b`. A popup lists the boards, for example `[1] home  [2] lab  [3] work`.
   A board is a file `Boards/*.md` in the vault with the line `kanban-plugin: board`.
2. Press the number of a board. To cancel, press Esc or `ctrl+c`.

The orchestrator is a normal claude agent in the workspace `<board> orchestrator` of
your session. Its first tab has the name "orchestrator". That workspace gets the focus.
When an orchestrator of the board already runs there, `ctrl+b` `shift+b` focuses it and
starts no second one. When Herdr cannot read your workspaces, no orchestrator starts.

A notification "Starting the orchestrator of the board <board>." shows at once. Then
claude starts in the vault folder (`$OBSIDIAN_VAULT_PATH`) with effort high.
When claude asks a question at the start (for example the trust of the vault folder),
answer it in the pane: the plugin waits up to 10 minutes. Claude then runs `/board-orchestrator <board>`. The agent name is `<board>-orchestrator`. The orchestrator
starts the due automatic tasks at once and asks the user which other cards to start. It
opens a worker for each. The workers run in the hidden Herdr session `board-workers`,
not in your sidebar. Each worker opens as a tab in the workspace `<board> workers` of
that session, in its project folder. The focus does not change. Workers never merge a PR:
`policy-set` adds deny rules for the merge commands.

When you close the workspace `<board> orchestrator`, the orchestrator stops. Its workers
go on in the hidden session. To start a new orchestrator, press `ctrl+b` `shift+b` and
the number of the board.

When a worker needs you, Herdr shows a notification `<agent> needs you`. The
orchestrator opens a view tab of the worker in the workspace `<board> orchestrator`, with
no focus, and gives you the link of the view pane. When that workspace is gone, the
view does not open. A worker needs you when it waits at a permission prompt,
ends its turn with no report, or writes a report that asks for you. When a worker ends
its turn while a background job runs, the orchestrator reads the last message of the
worker. It alerts you only when that message asks you something. When a worker ends
a new turn after its report and does not write the report again, the orchestrator reads
the last message. When the work is done, it tells the worker to write the report again.
When a worker is
gone with no report, the orchestrator tells you and closes its tabs. To see a worker at
another time, ask the orchestrator: it opens a view tab. When a worker finishes its
task, the orchestrator closes its tab and its view tab, with all the panes of the view
tab, for example a reviewr. The card then gives the claude
session ID: run `claude --resume <id>` to open the session again. When you look at the
view, the orchestrator waits until you leave it.

A new orchestrator finds the running workers of its board and watches them again, so you
can restart it at any time. To restart it, first stop it with `ctrl+b` `shift+x`.

When a worker needs you, the orchestrator writes nothing: the Herdr notification and the
agent list show it. Answer the worker in its view. When you tell the orchestrator which
worker gets your words ("tell the worker of <card> ..."), it sends your exact words to
that worker when the worker is idle and you do not have its view focused. With no such
words, it sends nothing to a worker that exists: it starts a new worker, or asks you.

A view pane is a Herdr agent (in the sidebar agent list) only in 2 cases. First, when the
worker needs you: the orchestrator reports the view blocked, so the view tab and the
orchestrator workspace show red. The orchestrator does not stop. The red goes when the
worker works again or ends a new turn. Second, while a reviewr pane is open in the tab of
the view: reviewr sends its notes only to an agent, so ctrl+b d in a view reports the view
at once with the state of the worker (working or idle), the project as its label and the
worker name (when no pane of yours has that name). The notes then go through the view to
the worker. At other times the view is released and is not in the list. `dispatch.sh
count-watch` copies each status change of a worker to its view by this rule, and the
hooks of `pane.closed` and `pane.exited` run `dispatch.sh views-sync`: it releases a view
that is no red when its reviewr is closed. A new `[[events]]` hook in the manifest needs
the plugin to load again (see `herdr plugin link`).

The workspace `<board> orchestrator` shows the number of workers of the board ("2
workers") and the number that work ("1 working"). Herdr shows a claude as idle when its
turn ends, also when a background agent or a background shell of that claude still
works. So an idle worker counts as working when the agent list of its screen shows a
background agent (a row that starts with "◯"). It also counts as working when the footer
below the input box shows a running shell ("1 shell" or "3 shells"). `dispatch.sh count-watch` keeps these
numbers up to date. It listens to the Herdr events of the hidden session and counts again
when the status of a worker changes, and after each pane event (a new or a closed
pane). `board.sh` and `dispatch.sh start` start it in the background. Only one listener
runs for each hidden session. It stops when the session stops. It also counts a board
with no workers workspace: when the last worker ends, the board shows 0 workers. When `dispatch.sh` or `lib.sh` changes (a `git pull`, an edit), the listener
restarts with the new code at the next event and counts again at once.

To see all workers, run `herdr session attach board-workers` in a terminal outside
Herdr. To stop all workers, run `herdr session stop board-workers`. The hidden session
starts with the environment of the default Herdr server. When an SSH session started that
server, it has no display: the hidden session then gets `DISPLAY`, `XAUTHORITY` and
`WAYLAND_DISPLAY` of the desktop session, so that a mouse copy in a view tab works. A
hidden session that started with no display gives its panes none. So before each Claude
start there, the plugin exports the desktop display in the shell of the pane.

The orchestrator reads the board with one call: `board-scan.sh cards <board>`. The script
reads the board file, the task notes and the project notes, and prints one JSON line for
each card in `📥 Backlog`, `📋 This Week`, `🔨 In Progress` and `⏳ Waiting On`. Each line has
the exact title and context lines, the date, the owner, the task note fields (`mode`,
`recurrence`, a prompt block), the `repo:` folder, the push policy and the number of
read-only rules. The last line gives the number of cards in `✅ Done` and the date. A
context line has at most 200 characters, with no count for the tab at the start. For a
longer one, `cards` gives only the first 200 characters and `context_long: true`, so that
a long card does not fill the orchestrator context. `board-scan.sh rules` prints the
sections of the vault `_CLAUDE.md` that the orchestrator follows. The script only reads
files.

To check one card just before an edit, the orchestrator runs `board-scan.sh card <board>
<text>`. It prints the same JSON lines as `cards`, but only for the cards whose title has
the text (a fixed text, in any case), and then the summary line of `cards`. It gives the
full context line of a long card. The summary
line gives the blank lines after the headings and the top card of `✅ Done` after the
edits of the user. The orchestrator uses them for the move of a card. The full `cards`
output of a board can be more than 10 000 characters, and the orchestrator context keeps
each output.

To dispatch an automatic task, the orchestrator runs `board-scan.sh prompt <task>`. It
prints only the prompt block under `## Prompt` of the task note. The orchestrator does
not read the full note: `dispatch.sh run-add` adds each report under `## Runs`, so the
note gets larger each run. The command exits 1 when the note has no prompt block, and 2
when the note does not exist.

Each phone message is a file `_inbox/<datetime>.md` in the vault.
`board-scan.sh inbox` prints one JSON line for each `*.md` file there, oldest first:
`file`, `text` (cut at 2000 characters) and `truncated`. The glob skips a dot file, so a
Syncthing temp file of a message that is not complete does not show. The last line gives
the count and the project notes that the cards of each board link to, so that the
orchestrator can tell which board a message goes to. After the orchestrator adds a card
for a message, `dispatch.sh inbox-clear <file>` deletes the file: the vault MCP tools
cannot delete. It accepts only `_inbox/<name>.md` with no dot at the start of the name,
and exits 2 for another path. It exits 1 when the file is gone, for example when the
orchestrator of another board made a card of it first.

The orchestrator also does not read a full report. `dispatch.sh report <report>` prints the
first line, the `## Result` section, the `## Vault changes` section, the `REFUSED:` lines
and a last line `full report: <report> (N lines)`. A report with no `## Result` section
gives its first 40 lines. Each section stops at 60 lines, with a line that tells the
number of cut lines. The worker prompt asks for a `## Result` section of at most 10 lines
after the first line.

A card is a short pointer, and its task note has the details. For a card with
`context_long: true`, the orchestrator runs
`dispatch.sh note-add <note> <board> <line> <title>`. The script copies the context lines
of the card at that line to the task note, under `## Notes`, then
`### YYYY-MM-DD, from the board`. The text does not go through the orchestrator context.
Then the orchestrator writes a short context line on the card. The script exits 1 and
changes nothing when the line is not the title line of that card (the user edited the
board), when the card has no context line, or when the card has task links and none is
the note.

For a recurring card, the vault keeps the full report of each run: the report files are
on one host only. `dispatch.sh run-add <note> <report>` copies the report into the task
note `<note>` (the path in the vault, for example `Tasks/X.md`) under `## Runs`, then
`### YYYY-MM-DD` (today). The report text does not go through the orchestrator context,
and the orchestrator does not read the task note. The script adds `## Runs` at the end of
a note that has no `## Runs` section. It puts the run after the last run, before the next
`## ` heading when one follows. An entry of today is there when the orchestrator records
the same card again on the same day: the script replaces that entry. It demotes the report
headings by 3 levels (`#` becomes `####`), but not a `#` line in a code block. It keeps
the frontmatter and sets `updated:` to today when the note has that field. It writes a
temp file in the same folder, then moves it on the note. Exit 2 is a usage error, exit 1
is no vault path or no note.

The orchestrator keeps a work log in the vault. Each time that it records a card result
on the board (done, waits for the user, an error, a new task, a recurring run), and when
the user gives a decision for a card, it writes the text to a file and runs
`dispatch.sh log <board> <file>`. A card title on the command line can run as a command,
for example with a backtick or a `$`. The text is the card title, the result in one line,
the links and the report path. A line end in the text becomes a space. The command adds
the line `- HH:MM <text>` under `## Log` of the note
`Dev Logs/YYYY-MM-DD - <board> (board orchestrator).md`. When the note does not exist, it
creates it with AI-first frontmatter (`type: devlog`, `board: "[[Boards/<board>]]"`) and a
`## For future agent` paragraph. When the daily note `Daily/YYYY-MM-DD.md` exists and has no
link to the log note, the command adds a link at the end of its `## Work` section (or at
the end of the note when there is no such section). It never creates a daily note. The work
history thus stays in the vault, not only in the orchestrator conversation.

Before the orchestrator starts a worker for a board task, it runs `dispatch.sh policy
<repo>`. The push policy of a project is `deny`, `ask` or `allow`:

- `deny`: `.claude/settings.json` or `.claude/settings.local.json` of the project has a
  `Bash(git push*)` rule in `permissions.deny`. Claude refuses a push.
- `ask`: `.claude/settings.json` or `.claude/settings.local.json` of the project has a
  `Bash(git push*)` rule in `permissions.ask`. Claude asks the user before a push.
- `allow`: one of these files has the rule in `permissions.allow`. The worker pushes,
  opens PRs and comments with no question.
- `missing`: no file has the rule. When more than one list has the rule, `deny` wins,
  then `ask`.

When the policy is `missing`, the orchestrator asks the user: "Can workers in `<repo>` push,
open and close PRs, and comment on PRs and issues with no question? Workers never merge."
Then it runs `dispatch.sh policy-set <repo> allow` or `dispatch.sh policy-set <repo> ask`.
`policy-set` adds 11 rules (`git push` and the `gh` calls that open, close and comment) to
`.claude/settings.local.json` of the project, and 4 merge rules to `deny`. When the
`origin` remote is not on `github.com`, it uses the Forgejo tools in place of `gh`, and removes
only the `gh` rules that it wrote. `dispatch.sh start task` refuses a project with no policy.

An automatic worker runs with only the rules of `.claude/settings.readonly.json` of the project.
See [Read-only checks](#read-only-checks). The orchestrator writes the reports in
`~/.local/state/board-orchestrator/`. The popup reads the boards from the vault path:
`$OBSIDIAN_VAULT_PATH`, else `env.OBSIDIAN_VAULT_PATH` in `~/.claude/settings.json`.

After the orchestrator records a report, it runs `dispatch.sh watch <pane> <report>` in the
background. The user can talk to the worker in its tab, and the worker can write the report
again. `watch` exits 0 when the content or the modification time of the report changes. The
orchestrator then records the report again: the new result replaces the earlier result for
that card. `watch` exits 1 when the agent stops and the report did not change.

`wait` and `watch` subscribe to the Herdr events of the worker pane. A status change of the
worker starts the next check at once. An idle worker needs 2 idle checks in a row, because
a short idle can occur before the work starts. With events, the second check comes after
`DISPATCH_SETTLE` seconds (default 5). No event tells of the report file or of a background
job on the screen. Thus a check also occurs each `DISPATCH_POLL` seconds (default 30). When
the events do not work (no socket, no `nc`, or an error), `wait` and `watch` check each
`DISPATCH_POLL` seconds only.

A worker does not edit the vault. When the user asks the worker for a change to the board or
to a task note, the worker writes the change in the report under `## Vault changes`. For a new
task, it writes only the title, the project, the priority and one context line. For a
change to existing text, it writes the note path and the exact old and new text. The orchestrator adds a new task from the
worker of a board task with no question. It shows each other change to the user and applies
only the changes that the user approves.

### Stop and start an orchestrator again

Press `ctrl+b` `shift+x` to stop an orchestrator. With two or more, a popup asks for the
board, and closes at once. A notification shows at once, and the stop continues in the
background. The stop first checks the workspace `<board> orchestrator`: each pane must be the
orchestrator, a worker view or a shell. When a pane runs another program, or when Herdr
cannot read the workspace, a notification tells you why, and nothing changes.

The stop then closes the workspace `<board> orchestrator`. The close stops claude, so no
`/exit` is necessary. When the close fails, a notification tells you, and nothing
changes. The workers in `<board> workers` of the hidden session go on. A stop and a
start of the same board do not run at the same time: one waits for the other.

Press `ctrl+b` `shift+b` and pick the board to start the orchestrator again. A new
claude session starts and gets `/board-orchestrator <board>`. It reads the board again
and finds its workers.

After a Herdr restart, Herdr resumes the orchestrator claude in its pane, with its old
context. The worker view tabs of the workspace `<board> orchestrator` come back as
shells, without their attach. The plugin repairs this by itself. Its startup hook
(`startup.sh`, `[[startup]]` in the manifest) returns at once and runs
`dispatch.sh views-restore --wait` in the background. That command polls every 5 seconds,
for up to 3 minutes, until the hidden session and its workers are back. For each worker
that runs a claude, it finds the workspace `<board> orchestrator`. It skips a board with
no such workspace. In the workspace it closes each tab (not the orchestrator tab) whose
panes all show only the login shell. It never closes a tab with another program. Then it
opens the view of each worker that has none, with no focus. A second run changes nothing.
The hook then sends each running orchestrator one prompt (`dispatch.sh restart-notice`): its background `wait` and `watch` commands stopped, so it runs `workers` again. The prompt waits until the orchestrator is idle (5 minutes at most). The hook then starts `dispatch.sh count-watch` if it does not run. `ctrl+b` `shift+b` on
an open board runs `dispatch.sh views-restore` once, as a manual fallback. Errors go to
`board.log` in the plugin state folder. When the host stops, the hidden session of the
workers stops too. The next `dispatch.sh start` starts it again.

## Read-only checks

An automatic worker gets its allow list from `.claude/settings.readonly.json` in the project. The
file is a Claude settings file:

```json
{"permissions": {"allow": ["Read", "Bash(make check)"]}}
```

`dispatch.sh start auto` starts claude with `--setting-sources user --settings
<repo>/.claude/settings.readonly.json --permission-mode dontAsk`, and with `--mcp-config
<repo>/.mcp.json` when that file exists. It adds one rule for the report file:
`--allowedTools Edit(//<report>)`. The prompt lists the rules. Claude refuses all other
calls. When the file is missing, is not valid JSON, or has no allow rule, `start auto`
exits 2 and opens no tab.

Facts from probes with the real worker flags:

- `--mcp-config .mcp.json` loads the project MCP servers with
  `--setting-sources user`.
- A file write needs an `Edit(//abs/path)` rule. A `Write(//abs/path)` rule matches
  nothing.
- Claude allows read-only commands such as `ls` on its own.
- Refused, no file created: command substitution (`echo $(touch /tmp/x)`), backticks
  (`` echo `touch /tmp/x` ``), and redirects (`printf x > /tmp/x`, `printf x > ./x`).
- Refused: a make target that the rule does not give
  (`echo 1 | make check help`).
- Refused: `nix flake show`, a command that the project settings allow. The worker does
  not load the project settings.
- Allowed and ran: the exact rules, for example `echo hello` and
  `echo "1 + 1" | make check`. Keep the rules exact: put no
  wildcard after a make target.

## Open a shell tab

1. Focus a pane in the workspace and folder that you want.
2. Press `ctrl+b` `c`.

A new tab opens with a shell and gets the focus. No popup opens and claude does not start.

The folder of the tab follows the same rule as `ctrl+b` `a`. In a linked git worktree,
the tab starts in the root of the main worktree. Else, it starts in the folder of the
focused pane. If no pane has focus, Herdr gives the tab its default folder.

This key replaces the Herdr default new tab key.

## Agent names follow the session title

A Claude Code SessionStart hook gives each claude in a Herdr pane its session title as
agent name. This applies to all claude sessions, also to claude that you start by hand.

1. Claude starts. The hook makes sure that one listener runs for the Herdr session of
   the pane. A second hook finds the running listener and exits at once.
2. The listener subscribes to the Herdr events `pane.updated` and `pane.agent_detected`.
   After the subscription starts, it checks each claude of the session once.
3. Herdr sends `pane.updated` when the terminal title of a pane changes. For a claude
   pane, the listener reads the agent name. When the slug of the title is not the agent
   name, the listener renames the agent.
4. The listener stops when the Herdr session stops. When `lib.sh` or `sync-name.sh`
   changes, the listener starts again with the new code. When the connection breaks,
   the listener connects again after 1 second.

The shell of a new tab is not always at its prompt when the plugin starts claude in it.
Herdr then refuses the start with `agent_pane_busy`. The plugin tries again each 0.2
seconds, for up to `AGENT_TABS_START_BUSY_WAIT` seconds (default 10).

To rename an agent, type `/rename <name>` in claude. The sidebar shows the new name at
once. The listener keeps the name while the title is `claude` or `Claude Code`, so the
name from the prompt or the handoff focus stays until claude gives a title.

A name that you give with `herdr agent start <name>` stays. The listener renames an
agent only when its name is empty, a start name (`claude-start-` and the pane ID, or
`claude` from older versions), or a name that the listener gave. The
listener keeps the names that it gave in a file next to its lock. So
`herdr agent wait <name>` works for the full session.

When `nc` or `flock` is missing, or when Herdr refuses the subscription, the hook uses
the old loop. The loop reads the title of its pane every 2 seconds and stops when claude
exits.

## Focus a pane or a tab from a link

Ctrl-click a link of the form `https://herdr.invalid/pane/<pane ID>` or
`https://herdr.invalid/tab/<tab ID>` in a pane. The link handler `herdr-link` runs the
action `focus-link`:

- For a tab link, the action focuses the tab.
- For a pane link, the action focuses the tab of the pane, then the agent in the pane.
  Herdr has no API to focus a pane by ID, so a pane without an agent gets only its tab.
- For a pane or a tab that does not exist, the action writes the cause to the log.

The host `herdr.invalid` never resolves. Herdr detects `https://` URLs and OSC 8 links,
but not a custom scheme such as `herdr://`. `claude/CLAUDE.md` tells claude to write
each pane and tab ID as such a link.

The terminal must send the Ctrl-click to Herdr. Ghostty does (tested 2026-10-09). GNOME
Terminal opens the link in the browser itself, so Herdr never gets the click.
`scripts/programs/ghostty` installs Ghostty.

## Open a file from a link

Ctrl-click a link of the form `file:///<path>` in a pane. The link handler `file-link`
runs the action `open-file`, and the file opens in Sublime Text. A line as `:12` or
`#L12` at the end of the link opens the file at that line.

Herdr opens only `http://` and `https://` links itself, so a file link needs the
handler. Claude writes a bare path as plain text, which is not a link.
`claude/CLAUDE.md` tells claude to write each file path as a `file://` link.

## Open reviewr next to claude

1. Focus the claude pane.
2. Press `ctrl+b` `d`.

A [reviewr](https://github.com/persiyanov/herdr-reviewr) pane opens to the right of the
pane and gets the focus. The tab zooms on reviewr. To see claude again, turn off the zoom.
reviewr opens in the scope "last turn": the changes of the most recent claude turn.
`herdr/reviewr.toml` sets this scope for all reviewr panes.

The action uses the git worktree of the most recent work of claude in the pane. The
Claude Code hook `track-worktree.sh` records this worktree after each Edit, Write,
MultiEdit, NotebookEdit and Bash tool call, also for subagents. A new session or
`/clear` deletes the old record, and so does the end of the session. A compact or a
resume keeps it. Without a record, the action uses the folder of the pane.

The hook takes the folder of the edited file. For a Bash command, it takes the last
`cd` or `git -C` target, for example `cd ../my-repo-123 && git commit`. A relative
target starts from the folder of the previous `cd`. The hook ignores `cd` in heredocs,
in quoted text and in `#` comments. Claude Code puts the Bash folder back to the project
folder after a `cd` out of the project. So a Bash command without a valid target uses the
folder where the command runs (the hook cwd) only when it is not in the worktree of the
project folder. The hook keeps only folders in the same repo as the session. A note in
the vault or a file in `/tmp` does not change the record.

In the `pre` mode, the hook also guards the board workers. A worker in the hidden
session (`$DISPATCH_SESSION`, default `board-workers`) cannot run `herdr pane split`,
`tab create`, `workspace create`, `worktree create`, `worktree open`, `plugin pane open`,
`plugin action` or `agent start`. The user cannot see a new pane or tab in that session.
The hook blocks the Bash call with exit 2 and tells the worker why. Commands that read
or use an existing pane stay allowed.

- If the tab already has a reviewr for the same worktree, the action zooms on that
  reviewr and opens nothing. Herdr cannot focus a pane by ID. The worker does not
  start, so a target that you chose in that reviewr stays.
- The action never closes a reviewr: reviewr keeps the comments that it did not send
  only in its memory.
- A reviewr follows the turns of a claude in its worktree. For a claude in another
  worktree, the reviewr reads the turn start only when its pane starts. The action
  records the turn start of each pane that it opens. When the turn start changed, the
  zoom shows the toast "reviewr shows an older turn. Close it, then press ctrl+b d to
  see the new turn.", also without debug.
- If the focused pane is a reviewr, the action does nothing.
- A reviewr in another tab, or for another worktree, does not stop the action.
- Outside a git repo, the action opens nothing.
- The action writes each result to the plugin log. In debug, it also shows a toast.

reviewr diffs against a target branch. The action sets it in this order:

1. The base branch of the pull request. After a new pane opens, a background worker runs
   `gh pr view` in the worktree, with a time limit of 15 seconds. reviewr reads the
   target again at each refresh, so the change shows some seconds later. This target
   replaces a target from the reflog and a target that you chose in reviewr.
2. The branch that the worktree branch started from, in the reflog. The action writes
   it before the pane opens, only when the worktree has no target yet. It skips a
   branch made from `HEAD` or from a commit ID.
3. The reviewr default: the default branch of the repo (`origin/HEAD`).

The action stores the target in the ref `refs/worktree/reviewr/base-pick`, as the
reviewr picker does. For the default branch, it deletes the ref. Without a pull
request, or when `gh` fails, the worker changes nothing.

reviewr records the start of a turn only while a reviewr pane is open. So the hooks
record it too, and a pane that you open after the turn shows the turn:

1. When you send a prompt, the `prompt` hook makes a snapshot of the recorded worktree
   and of the worktree of the hook cwd. A snapshot is a tree object of all the files. It
   does not change the index, the files or a ref.
2. Before each tool call, the `pre` hook adds a snapshot of a worktree that the turn
   moves to.
3. When claude stops, the `stop` hook makes the snapshots again. For each worktree that
   changed, it writes the turn start as `refs/worktree/reviewr/turn-base`. A turn that
   changes no file keeps the old turn start, as in reviewr. Then the hook deletes the
   turn file, so a second Stop in the same turn does nothing.

Claude Code runs no Stop hook after an Esc. So when the turn file is still there, the
`prompt` hook first ends that turn as the `stop` hook does, then records the new turn.

A new session, `/clear` and the end of the session delete the turn file. A compact or a
resume keeps it.

The reviewr action `open` is different: it opens one reviewr for each workspace, for the
focused pane.

## Hand off a conversation

1. Focus a claude pane that is idle. The handoff does not start if claude is working or waits for an answer.
2. Press `ctrl+b` `shift+a`. A popup opens.
3. Type the focus of the next session, for example `fix the login test`. To skip it, press Enter on an empty line.
4. Press one key for the effort of the new claude, as in "Start a conversation". To
   keep the claude default, press Enter.
5. Press one key for the focus of the new tab, as in "Start a conversation". To keep the
   focus on your pane, press Enter.
6. Wait. The old claude runs `/handoff` and writes `/tmp/herdr-handoff-<time>-<pid>.md`.
7. A new tab opens. The plugin gives its claude a session title with `/rename`: the focus
   text from step 3, else the old title with `handoff`, for example `Postgres port issue handoff`.
8. The new claude reads the document and continues the work.
9. The agent gets the session title of claude as its name. If the old session has no
   title and you give no focus, claude makes a title. Without a title in 60 seconds, the
   sidebar shows `claude`.

If claude asks for permission to write the file, answer the question in the old pane.
The handoff waits up to 15 minutes. The old tab stays open, so close it when you no
longer need it. To cancel in the popup, press Esc or `ctrl+c`.

## Run /handoff by hand

In claude, type `/handoff <focus>`. Claude writes the document in the temporary folder
and shows the path. This does not open a new tab. The skill is in
`claude/skills/handoff/SKILL.md`.

## When something fails

- To see the cause, run `herdr plugin log list --plugin awea.agent-tabs`. If claude
  does not start in the new tab, the log also shows the path of the handoff document.
- To also show each error as a Herdr toast, turn on debug:
  `touch "$(herdr plugin config-dir awea.agent-tabs)/debug"`.
  To turn it off, remove that file.
- To see the background logs, run
  `find ~/.config/herdr ~/.local/state -name 'handoff.log' -o -name 'new-tab.log' -o -name 'sync-name.log' -o -name 'reviewr.log'`.

## Install on a new machine

Run these commands from the root of the dotfiles:

```bash
make links           # links herdr/config.toml, the reviewr config, the /handoff skill, the name and worktree hooks
make herdr-plugins   # installs the Herdr state hook, registers the agent-tabs plugin in Herdr
herdr server reload-config
```

`make links` also links `claude/settings.json` as `~/.claude/settings.json`. That file
has the hooks: `herdr-agent-name.sh start`, and `herdr-worktree.sh` with the modes `start`
(`SessionStart`), `end` (`SessionEnd`), `prompt` (`UserPromptSubmit`), `stop` (`Stop`), `pre`
(`PreToolUse`) and `tool` (`PostToolUse`). The tool hooks use the matcher
`Edit|Write|MultiEdit|NotebookEdit|Bash`. After a compact, `herdr-compact-orchestrator.sh`
tells the claude of a board orchestrator to read its skill again. It also runs `herdr-agent-state.sh session`, the
hook of the Herdr integration for Claude.

`make herdr-hook` installs or updates `~/.claude/hooks/herdr-agent-state.sh`. Do not run
`herdr integration install claude`: it adds a second copy of the hook to
`claude/settings.json`, with the absolute path of the home folder. Run `make herdr-hook`
after each `herdr update`, for example from topgrade, in `~/.config/topgrade.toml`:

```toml
[commands]
"Herdr" = "herdr update && make -C ~/.workspace/dotfiles herdr-hook"
```

The plugin needs `bash` 4 or later and `jq`, in `/opt/homebrew/bin`, `/usr/local/bin`,
`/usr/bin` or `/bin`. On macOS, `/bin/bash` is bash 3.2: install bash with Homebrew. The
scripts then run again with that bash. The scripts use `setsid` and `flock` when they
exist (Linux). Without them (macOS), a subshell that ignores SIGHUP starts the background
workers and a lock folder keeps one name loop for each pane. The board orchestrator
(`board.sh`, `dispatch.sh`) always needs `flock`: on macOS, the Homebrew `flock` of the
`Brewfile`. The worker counts (`dispatch.sh count-watch`) and the fast `wait` and `watch` need an
`nc` with `-U` (Unix sockets): OpenBSD netcat, ncat or the macOS `nc`. netcat-traditional and the busybox `nc`
do not work.
The reviewr target of a pull request needs `gh`, and `timeout` (Linux) or `gtimeout` (macOS,
from the Homebrew `coreutils`).

## Files

| File | Use |
|---|---|
| `herdr-plugin.toml` | Manifest: the actions `new-tab`, `handoff`, `board`, `board-stop`, `new-shell-tab`, `focus-link`, `open-file`, `split-right`, `split-down` and `reviewr`, the link handlers `herdr-link` and `file-link`, the popup panes `new-tab-prompt`, `handoff-prompt`, `board-prompt` and `board-stop-prompt`, and the startup hook. |
| `lib.sh` | Shared helpers: `notify` (log, and a toast in debug), `detach`, `read_effort`, `read_focus`, `pane_cwd`, `worktree_file`, `turn_file`, `main_worktree`, `view_worker`, `work_dir`, `start_claude`, `open_claude_tab`, `name_agent`, `rename_agent`, `sync_agent_name`, `vault_path`, `read_settings`, `push_policy`, `board_workspace_id`, `orchestrator_pane` (the orchestrator claude of a board in the session of the user), `orchestrator_boards`, `ensure_session` (starts the hidden session of the workers), `show_worker_count`. The workspaces plugin also uses this file. |
| `new-agent-tab.sh` | The `new-tab` action in three modes: `open` (opens the popup), `prompt` (popup), `worker` (background). |
| `board.sh` | The `board` action in three modes: `open` (opens the popup), `prompt` (popup), `worker` (background). |
| `startup.sh` | The `[[startup]]` hook: returns at once. In the background it runs `dispatch.sh views-restore --wait`, then `dispatch.sh restart-notice`, then `dispatch.sh count-watch`. |
| `new-shell-tab.sh` | The `new-shell-tab` action: opens a shell tab with the focus, in one step, without a popup. |
| `split.sh` | The `split-right` and `split-down` actions (`prefix+%`, `prefix+"`): split the focused pane. In the view of a board worker, the new pane opens in the folder of the worker. |
| `handoff.sh` | The `handoff` action in three modes: `open` (checks the agent), `prompt` (popup), `worker` (background). |
| `sync-name.sh` | The SessionStart hook in two modes: `start` (hook) and `loop` (background). `make links` links it as `~/.claude/hooks/herdr-agent-name.sh`. |
| `focus-link.sh` | The `focus-link` action: focuses the pane or the tab of a clicked Herdr link. |
| `open-file.sh` | The `open-file` action: opens the file of a clicked file link in Sublime Text. |
| `reviewr.sh` | The `reviewr` action in two modes: the action (opens reviewr right of the focused pane, for the recorded worktree or the folder of the pane, and writes the target from the reflog) and `base` (background, writes the target from the pull request). |
| `track-worktree.sh` | The Claude Code hook in six modes: `start` (SessionStart, deletes the record and the turn file), `end` (SessionEnd, the same), `tool` (PostToolUse, records the worktree), `prompt` (UserPromptSubmit, writes the turn file), `pre` (PreToolUse, adds a worktree to the turn file) and `stop` (Stop, writes the reviewr turn base). `make links` links it as `~/.claude/hooks/herdr-worktree.sh`. |
| `compact-orchestrator.sh` | The Claude Code hook for `SessionStart` with the matcher `compact`: a compact removes the text of the board-orchestrator skill, so the hook tells the claude of an orchestrator to read the skill again. Another claude gets no text. `make links` links it as `~/.claude/hooks/herdr-compact-orchestrator.sh`. |
| `dispatch.sh` | The tool of the board orchestrator: `policy` (prints the push policy of a project), `policy-set` (writes the push rules to `.claude/settings.local.json`), `start task` or `start auto` (opens a worker claude in a tab of the workspace `<board> workers` of the hidden session, in the project folder), `wait` (waits for the report of the worker), `report` (prints a summary of a report), `log` (adds a card result to the daily board note of the vault) and `count-watch` (keeps the worker counts of the orchestrator workspace up to date). |
| `board-scan.sh` | The read tool of the board orchestrator: `cards` (prints each card of a board with the fields of its task note and project, one JSON line per card), `card` (prints only the cards whose title has a text, and the summary line), `prompt` (prints the prompt block of a task note) and `rules` (prints the sections of the vault `_CLAUDE.md` that the orchestrator follows). |
| `../../../claude/skills/board-orchestrator/` | The `/board-orchestrator` skill: `SKILL.md`, and a `dispatch.sh` link and a `board-scan.sh` link to this folder. |
| `test/agent-tabs.bats`, `test/board-scan.bats` | Tests. |
| `test/fake-herdr` | A fake `herdr` for the tests. It logs each call and gives fixed JSON. |
| `test/fake-gh` | A fake `gh` for the tests. It logs each call and gives the base branch of a pull request. |
| `../../reviewr.toml` | The reviewr config: the scope "last turn". `make links` links it as `~/.config/herdr/plugins/config/persiyanov.reviewr/config.toml`. |

## Tests

```bash
bats herdr/plugins/agent-tabs/test/
shellcheck -x herdr/plugins/agent-tabs/*.sh herdr/plugins/agent-tabs/test/fake-herdr herdr/plugins/agent-tabs/test/fake-gh
```

With asdf, set the versions first:
`export ASDF_BATS_VERSION=1.8.2 ASDF_SHELLCHECK_VERSION=0.9.0`.
