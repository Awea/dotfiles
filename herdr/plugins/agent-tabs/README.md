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

1. Claude starts. The hook starts one background loop for the pane.
2. Every 2 seconds, the loop reads the terminal title of claude.
3. When the slug of the title is not the agent name, the loop renames the agent.
4. The loop stops when claude exits.

To rename an agent, type `/rename <name>` in claude. The sidebar shows the new name in
2 seconds. The loop keeps the name while the title is `claude` or `Claude Code`, so the
name from the prompt or the handoff focus stays until claude gives a title.

A name that you give with `herdr agent start <name>` stays. When the loop first finds
claude and claude already has a name other than `claude`, the loop stops. So
`herdr agent wait <name>` works for the full session.

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
`cd` or `git -C` target, for example `cd ../objkt-com-web-2426 && git commit`. A relative
target starts from the folder of the previous `cd`. The hook ignores `cd` in heredocs,
in quoted text and in `#` comments. Claude Code puts the Bash folder back to the project
folder after a `cd` out of the project. So a Bash command without a valid target uses the
folder where the command runs (the hook cwd) only when it is not in the worktree of the
project folder. The hook keeps only folders in the same repo as the session. A note in
the vault or a file in `/tmp` does not change the record.

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
`Edit|Write|MultiEdit|NotebookEdit|Bash`. It also runs `herdr-agent-state.sh session`, the
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
workers and a lock folder keeps one name loop for each pane.
The reviewr target of a pull request needs `gh`, and `timeout` (Linux) or `gtimeout` (macOS,
from the Homebrew `coreutils`).

## Files

| File | Use |
|---|---|
| `herdr-plugin.toml` | Manifest: the actions `new-tab`, `handoff`, `new-shell-tab`, `focus-link`, `open-file` and `reviewr`, the link handlers `herdr-link` and `file-link`, and the popup panes `new-tab-prompt` and `handoff-prompt`. |
| `lib.sh` | Shared helpers: `notify` (log, and a toast in debug), `detach`, `read_effort`, `read_focus`, `pane_cwd`, `worktree_file`, `turn_file`, `main_worktree`, `start_claude`, `open_claude_tab`, `name_agent`, `rename_agent`, `sync_agent_name`. The workspaces plugin also uses this file. |
| `new-agent-tab.sh` | The `new-tab` action in three modes: `open` (opens the popup), `prompt` (popup), `worker` (background). |
| `new-shell-tab.sh` | The `new-shell-tab` action: opens a shell tab with the focus, in one step, without a popup. |
| `handoff.sh` | The `handoff` action in three modes: `open` (checks the agent), `prompt` (popup), `worker` (background). |
| `sync-name.sh` | The SessionStart hook in two modes: `start` (hook) and `loop` (background). `make links` links it as `~/.claude/hooks/herdr-agent-name.sh`. |
| `focus-link.sh` | The `focus-link` action: focuses the pane or the tab of a clicked Herdr link. |
| `open-file.sh` | The `open-file` action: opens the file of a clicked file link in Sublime Text. |
| `reviewr.sh` | The `reviewr` action in two modes: the action (opens reviewr right of the focused pane, for the recorded worktree or the folder of the pane, and writes the target from the reflog) and `base` (background, writes the target from the pull request). |
| `track-worktree.sh` | The Claude Code hook in six modes: `start` (SessionStart, deletes the record and the turn file), `end` (SessionEnd, the same), `tool` (PostToolUse, records the worktree), `prompt` (UserPromptSubmit, writes the turn file), `pre` (PreToolUse, adds a worktree to the turn file) and `stop` (Stop, writes the reviewr turn base). `make links` links it as `~/.claude/hooks/herdr-worktree.sh`. |
| `test/agent-tabs.bats` | Tests. |
| `test/fake-herdr` | A fake `herdr` for the tests. It logs each call and gives fixed JSON. |
| `test/fake-gh` | A fake `gh` for the tests. It logs each call and gives the base branch of a pull request. |
| `../../reviewr.toml` | The reviewr config: the scope "last turn". `make links` links it as `~/.config/herdr/plugins/config/persiyanov.reviewr/config.toml`. |

## Tests

```bash
bats herdr/plugins/agent-tabs/test/agent-tabs.bats
shellcheck -x herdr/plugins/agent-tabs/*.sh herdr/plugins/agent-tabs/test/fake-herdr herdr/plugins/agent-tabs/test/fake-gh
```

With asdf, set the versions first:
`export ASDF_BATS_VERSION=1.8.2 ASDF_SHELLCHECK_VERSION=0.9.0`.
