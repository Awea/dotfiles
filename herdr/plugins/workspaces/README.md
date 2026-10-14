# workspaces

A local Herdr plugin that creates a new workspace in a folder that you choose in a
popup. The folders are `~/.workspace`, then the folders of
[z](https://github.com/rupa/z), the most frecent first. The workspace starts with a
shell, or with claude and your prompt.

## Shortcut

| Keys | Action | Result |
|---|---|---|
| `ctrl+b` `shift+n` | `awea.workspaces.new` | Opens the folder popup. Enter creates a shell workspace in the folder and gives it the focus. `ctrl+a` starts claude in the new workspace with a prompt. |

The key binding is in `herdr/config.toml`. It replaces the built-in "new workspace" key.

## Create a workspace

1. Press `ctrl+b` `shift+n`. A popup opens with the list of folders.
2. To use `~/.workspace`, press Enter.
3. To use a different folder, type part of its path. Then select it with the arrow keys
   and press Enter.

To cancel, press Esc or `ctrl+c`.

- The list shows each folder in the z data file (`$_Z_DATA`, `~/.z` by default) that
  exists. The order is the order of `z -l`, the most frecent first.
- Without `~/.workspace`, the first folder is `$HOME`.
- Without `fzf`, the popup does not open. The action creates the workspace in the first
  folder.

The workspace label is the name of the git repository of the folder. Outside a git
repository, the label is the name of the folder.

## Start claude in a new workspace

1. Press `ctrl+b` `shift+n`. A popup opens with the list of folders.
2. Select the folder and press `ctrl+a`.
3. Type the prompt and press Enter.
4. Press one key for the effort: `l` low, `m` medium, `h` high, `x` xhigh, `M` max.
   To keep the claude default, press Enter.
5. To give the focus to the new workspace, press `y`. To keep the focus on your pane,
   press `n` or Enter.

The workspace opens, and claude starts in its first pane with your prompt and effort.
These are the same questions and keys as `ctrl+b` `a` of the agent-tabs plugin.

- Claude starts in the folder that you select. The main worktree rule of `ctrl+b` `a`
  does not apply.
- An empty prompt in step 3 starts a clean claude.
- The agent gets the session title of claude as its name, as with `ctrl+b` `a`.
- In fzf, `ctrl+a` does not move the cursor to the start of the line. Use Home.
- To see the cause of a failure, read `new-workspace.log` in the plugin state folder:
  `find ~/.config/herdr ~/.local/state -name new-workspace.log`.

## Install on a new machine

Run these commands from the root of the dotfiles:

```bash
make links           # links herdr/config.toml
make herdr-plugins   # registers the plugins in Herdr
herdr server reload-config
```

The plugin needs `bash`, `fzf` and z with its data file. The `ctrl+a` flow also needs
the agent-tabs plugin next to this plugin, because it uses `../agent-tabs/lib.sh`. It
also needs `jq` and `setsid`.

## Files

| File | Use |
|---|---|
| `herdr-plugin.toml` | Manifest: the action `new` and the popup pane `pick`. |
| `new-workspace.sh` | The action in four modes: `open` (opens the popup), `list` (prints the folders), `pick` (popup), `worker` (background: creates the workspace and starts claude). |
| `test/workspaces.bats` | Tests. |
| `test/fake-herdr` | A fake `herdr` for the tests. It logs each call and gives fixed JSON. |
| `test/fake-fzf` | A fake `fzf` for the tests. It prints the key `$FAKE_KEY` and a fixed line of its input. |

## Tests

```bash
bats herdr/plugins/workspaces/test/workspaces.bats
shellcheck -x herdr/plugins/workspaces/*.sh herdr/plugins/workspaces/test/fake-*
```
