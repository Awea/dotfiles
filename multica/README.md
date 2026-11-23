# Multica perso trial

A local, self-hosted Multica (v0.11.1) for the perso board. The vault board stays the
source of truth. Design: `docs/superpowers/specs/2026-11-20-multica-perso-trial-design.md`
(not in git).

| Part | What |
|---|---|
| `bin.symlink/multica-perso` | `import` the open perso cards, `export` the Multica state, `status`. |
| `lib.sh` | The shared functions of `multica-perso`. |
| `bin.symlink/multica-agent` | Set up the agent user (`setup`), start its daemon (`daemon`), and share a local repo (`share`, `unshare`). |
| `multica-daemon.service` | The systemd unit of the daemon of the agent user. |
| `multica-git.service` | The systemd user unit of the git server of the shared local repos. |
| `agent-init` | The setup inside the agent session (`multica-agent-init`): logins and tokens. |
| `agent-instructions.md` | The instructions of the agent "perso-claude". |

The server is the role `multica` of the server-playbooks repo. It runs on this laptop for
now. The web page is http://localhost:3200 and the API is http://localhost:8080. Both
listen on 127.0.0.1 only. Telemetry is off. No LLM key, no email, no cloud storage.

## 1. Start the server

Follow the section "Multica (local trial)" of the server-playbooks README:
`make multica-local`, the sign-in with `make multica-local-code`, the workspace "perso"
(its issue keys are `PERSO-<n>`), then `make multica-local-lock`. Delete the welcome
issues of Multica: the export would give a new card for each of them.

## 2. Set up your own `multica` command

1. Download `multica-cli-0.11.1-linux-amd64.tar.gz` (or `-darwin-arm64`) and
   `checksums.txt` from https://github.com/multica-ai/multica/releases/tag/v0.11.1.
2. Run `sha256sum --check --ignore-missing checksums.txt` (on macOS: `shasum -a 256 -c`).
3. Put the `multica` binary of the archive in `~/.local/bin`.
4. Run `multica config set server_url http://localhost:8080` and
   `multica config set app_url http://localhost:3200`. Do not use `multica setup`: it
   also starts a daemon, and a daemon of your user runs agents with your keys.
5. Run `multica login`, then `multica workspace switch perso`.

## 3. Set up the agent user (Linux, needs sudo)

The agent runs Claude Code with all permissions of its OS user. The user `multica-agent`
keeps it away from your keys, your vault and your servers. Two commands do the setup.
Each one does nothing for a step that is already done, so you can run it again.

1. As yourself, run `multica-agent setup`. It makes the user `multica-agent` (with no
   `docker` or `sudo` group), adds you to its group, closes your home to others, copies
   `claude/CLAUDE.md` and your `multica` command, installs Claude Code for it, points
   its `multica` at the local server, and installs the systemd unit
   `multica-daemon.service`. When it says so, log out and in.
2. Make one GitHub fine-grained token per owner, each with only "Contents: read" on the
   private repos of that owner. The public repos need no token. As of 2026-11-20:
   `Awea` (`game-guesser`, `signal-bot`) and `wearemd` (`server-playbooks`, the org must
   allow fine-grained tokens).
3. Run `sudo -iu multica-agent`, then `claude`. Answer Yes to the trust question and log
   in with your Claude account. Then quit Claude.
4. In the same session, run `multica-agent-init`. Open the Multica link that it prints in
   your browser. Paste each token when it asks: the input is hidden. It checks each token.
5. As yourself, run `multica-agent daemon`. It enables and starts the systemd service
   `multica-daemon`, which runs the daemon as `multica-agent`. The daemon runs five runs
   at a time. `when-free` does not see these runs: no check of CPU or RAM gates them.
   It starts again after a reboot. Read its log with `journalctl -u multica-daemon`. Stop
   it with `sudo systemctl disable --now multica-daemon`.

## 4. Make the agent

1. Run `multica runtime list`. The runtime "Claude (<host>)" of `multica-agent` is online.
2. Make the agent "perso-claude" on it, private to you, five runs at a time, with the text
   under the line of `agent-instructions.md`:
   `multica agent create --name perso-claude --runtime-id <id> --permission-mode private --max-concurrent-tasks 5 --instructions "$(awk 'f; /^---$/ {f=1}' multica/agent-instructions.md)"`

## 5. Share a local repo

Multica takes only a repo URL with a host (`https`, `ssh` or `git`), and the agent cannot
read your home. So a git server of your user gives your local repos to the agent, with no
GitHub. It listens on 127.0.0.1:9418 only, and it is read-only: the agent never pushes.
It serves only the git folder of each shared repo: not a link or another repo in it.

1. Make sure that the repo has a commit. For a new project, run `git init` and make a
   first commit.
2. Run `multica-agent share <repo folder>`. It serves the repo as
   `git://localhost/<name>` and adds that URL to the workspace "perso". `<name>` is the
   folder name of the repo, with no `.git` suffix.
3. Run `multica repo list` to see the shared repos. Read the log of the server with
   `journalctl --user -u multica-git`.
4. To stop the share of a repo, run `multica-agent unshare <name>`. The server
   stops after the last repo.

Each local user can read a shared repo. On this laptop, that is you and `multica-agent`.
The server is a systemd user unit: it runs while you are logged in.

## 6. Use it

1. Run `multica-perso import`. Each open perso card gets an issue. Run it again after
   each change of the board: it updates the issues and makes no duplicate.
2. In Multica, assign an issue to "perso-claude". The run starts.
3. Run `multica-perso export` at once. It writes `_multica/perso.md` (the Multica state in
   the board format) and `_multica/perso.changes.md` (the changes) in the vault.
4. The perso orchestrator shows the open changes in its "Multica" list, and applies the
   ones you approve. It starts no worker on a card that is with a Multica agent.
5. Review an agent branch: find its repo with
   `find /home/multica-agent/multica_workspaces -maxdepth 5 -name .git`, then in your
   repo run `git fetch <that repo folder> multica/<KEY>`. When git refuses the folder of
   another owner, add `-c safe.directory=<that repo folder>` after `git`.
6. Run `multica-perso status` to see the server, the issues and the open changes.

## 7. The way back to the vault

`_multica/perso.md` holds each issue as a card of the perso board format. To end the
trial, apply the open changes with the orchestrator, or copy the cards of
`_multica/perso.md` into `Boards/perso.md`.

## 8. Remove it

1. In server-playbooks, run `make multica-local-down`, then
   `docker volume rm multica_pgdata multica_backend_uploads`.
2. Run `sudo systemctl disable --now multica-daemon`, then
   `sudo rm /etc/systemd/system/multica-daemon.service` and `sudo systemctl daemon-reload`.
   Run `sudo userdel -r multica-agent`. Revoke its GitHub tokens.
3. Run `multica-agent unshare <name>` for each shared repo, then
   `rm ~/.config/systemd/user/multica-git.service` and `systemctl --user daemon-reload`.
4. Delete `_multica/` in the vault after the cards are back in `Boards/perso.md`.
5. Delete `multica/`, `bin.symlink/multica-*` and `bin.symlink/test/multica-*` in the
   dotfiles, and the `multica` parts of the board-orchestrator. Delete the role
   `multica` in server-playbooks.
