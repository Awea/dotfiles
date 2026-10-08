# workspaces

A local Herdr plugin that creates a new workspace in a folder that you choose in a
popup. The folders are `~/.workspace`, then the folders of
[z](https://github.com/rupa/z), the most frecent first.

## Shortcut

| Keys | Action | Result |
|---|---|---|
| `ctrl+b` `shift+n` | `awea.workspaces.new` | Opens the folder popup, then creates a workspace in the folder and gives it the focus. |

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

## Install on a new machine

Run these commands from the root of the dotfiles:

```bash
make links           # links herdr/config.toml
make herdr-plugins   # registers the plugins in Herdr
herdr server reload-config
```

The plugin needs `bash`, `fzf` and z with its data file.

## Files

| File | Use |
|---|---|
| `herdr-plugin.toml` | Manifest: the action `new` and the popup pane `pick`. |
| `new-workspace.sh` | The action in three modes: `open` (opens the popup), `list` (prints the folders), `pick` (popup). |
| `test/workspaces.bats` | Tests. |
| `test/fake-herdr` | A fake `herdr` for the tests. It logs each call. |
| `test/fake-fzf` | A fake `fzf` for the tests. It prints a fixed line of its input. |

## Tests

```bash
bats herdr/plugins/workspaces/test/workspaces.bats
shellcheck -x herdr/plugins/workspaces/*.sh herdr/plugins/workspaces/test/fake-*
```
