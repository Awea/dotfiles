# agent-tabs

A local Herdr plugin that opens claude, or a shell in the main git worktree, in a new tab.
Claude starts a conversation with your prompt, or it continues the focused conversation
with a `/handoff` document.

The plugin also gives each claude in Herdr its session title as agent name, and changes
the name after `/rename`. The `/reviewr` command of claude opens reviewr next to claude.

## Shortcuts

The prefix is the Herdr default, `ctrl+b`.

| Keys | Action | Result |
|---|---|---|
| `ctrl+b` `a` | `awea.agent-tabs.new-tab` | Asks for a prompt, an effort level and the tab focus, then starts claude with them in a new tab. In a linked git worktree, claude starts in the root of the main worktree of the repo. Else, claude starts in the folder of the focused pane. The tab opens in the background by default. The sidebar shows the session title of claude as the agent name. An empty prompt opens a clean claude tab. |
| `ctrl+b` `shift+a` | `awea.agent-tabs.handoff` | Moves the focused claude conversation to a new tab with `/handoff`. |
| `ctrl+b` `c` | `awea.agent-tabs.new-shell-tab` | Opens a shell tab without claude and gives it the focus. The tab starts in the same folder as the `ctrl+b` `a` tab. |

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
the cursor. The focus line of the handoff popup uses the same keys.

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

## Open reviewr next to claude

In claude, type `/reviewr`. A [reviewr](https://github.com/persiyanov/herdr-reviewr) pane
opens to the right of the claude pane and gets the focus. The tab zooms on reviewr. To see
claude again, turn off the zoom. The command finds the git worktree for reviewr in this
order:

1. The folder that you give: `/reviewr ../infrastructure-pds`.
2. The worktree of the last file that claude edited in the session, in the git repo of
   the current folder of claude. This can be a different worktree than the current folder.
   Outside a git repo, the last edit in any git repo.
3. The current folder of claude.

For step 2, Herdr gives the claude session ID of the pane. The script reads the edits
(Edit, Write, MultiEdit and NotebookEdit) in the session transcript in
`~/.claude/projects`. An edit with a Bash command, for example `sed -i`, does not count.

- If the tab already has a reviewr for the same worktree, the command opens nothing and
  shows the pane ID of that reviewr.
- A reviewr in another tab, or for another worktree, does not stop the command.
- Outside Herdr or outside a git repo, the command shows the cause and opens nothing.

The reviewr action `open` is different: it opens one reviewr for each workspace, for the
focused pane. The skill is in `claude/skills/reviewr/SKILL.md`. Its `open.sh` is a link to
`reviewr.sh`.

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
  `find ~/.config/herdr ~/.local/state -name 'handoff.log' -o -name 'new-tab.log' -o -name 'sync-name.log'`.

## Install on a new machine

Run these commands from the root of the dotfiles:

```bash
make links           # links herdr/config.toml, the /handoff and /reviewr skills, the name hook
make herdr-plugins   # registers the agent-tabs plugin in Herdr
herdr server reload-config
```

`~/.claude/settings.json` is not in the dotfiles. Add the hook to the `SessionStart` hooks:

```json
{ "type": "command", "command": "bash $HOME/.claude/hooks/herdr-agent-name.sh start", "timeout": 10 }
```

The plugin needs `bash`, `jq` in `/usr/bin` or `/bin`, `setsid` and `flock` (Linux only).

## Files

| File | Use |
|---|---|
| `herdr-plugin.toml` | Manifest: the actions `new-tab`, `handoff`, `new-shell-tab` and `focus-link`, the link handler `herdr-link`, and the popup panes `new-tab-prompt` and `handoff-prompt`. |
| `lib.sh` | Shared helpers: `notify` (log, and a toast in debug), `read_effort`, `read_focus`, `pane_cwd`, `main_worktree`, `open_claude_tab`, `name_agent`, `rename_agent`, `sync_agent_name`. |
| `new-agent-tab.sh` | The `new-tab` action in three modes: `open` (opens the popup), `prompt` (popup), `worker` (background). |
| `new-shell-tab.sh` | The `new-shell-tab` action: opens a shell tab with the focus, in one step, without a popup. |
| `handoff.sh` | The `handoff` action in three modes: `open` (checks the agent), `prompt` (popup), `worker` (background). |
| `sync-name.sh` | The SessionStart hook in two modes: `start` (hook) and `loop` (background). `make links` links it as `~/.claude/hooks/herdr-agent-name.sh`. |
| `focus-link.sh` | The `focus-link` action: focuses the pane or the tab of a clicked Herdr link. |
| `reviewr.sh` | The `/reviewr` command: opens reviewr right of the claude pane, for the worktree of claude. |
| `test/agent-tabs.bats` | Tests. |
| `test/fake-herdr` | A fake `herdr` for the tests. It logs each call and gives fixed JSON. |

## Tests

```bash
bats herdr/plugins/agent-tabs/test/agent-tabs.bats
shellcheck -x herdr/plugins/agent-tabs/*.sh herdr/plugins/agent-tabs/test/fake-herdr
```

With asdf, set the versions first:
`export ASDF_BATS_VERSION=1.8.2 ASDF_SHELLCHECK_VERSION=0.9.0`.
