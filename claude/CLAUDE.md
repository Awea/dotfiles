# Workflow

- Use a subagent only for independent work that runs in parallel, or for a wide search
  that would put many file dumps into the main context. Do a task of a few tool calls
  inline. Each subagent starts at 20k to 30k tokens before it does any work.
- Use the Explore agent for a search, not general-purpose: it starts at about half the
  tokens.
- Subagents run on Sonnet by default (`CLAUDE_CODE_SUBAGENT_MODEL`). Pass `model: "opus"`
  for Explore and other search subagents and for review subagents.
- Set the subagent effort level: `high` for Explore and other search subagents, `low` for
  implementation subagents, `high` for review subagents.

# Git

- Write a commit message as a subject `<scope>: <summary>`, a blank line, then a body
  that tells what changes and why. When a repo has its own commit style, use that style.
  Its `CLAUDE.md`, its contributing docs or its recent `git log` show the style. For
  example, the dotfiles put a gitmoji before `<scope>: <summary>` and write no body.
- Never add a signature to commit messages: no `Co-Authored-By` trailer and no
  generated-by line. GPG signing stays on.
- Do not test the gpg-agent cache before a commit. When a commit fails to sign, ask the
  user to run `gpg-unlock`. Never use `--no-gpg-sign`.
- Write each issue or PR reference as a full link to the forge, never as a bare number:
  `[#656](https://forge.example/owner/repo/issues/656)` or
  `[PR #659](https://forge.example/owner/repo/pulls/659)`. This applies to chat replies,
  notes, docs and PR bodies. Comments on the forge and commit messages keep a bare `#N`,
  because the forge makes the link.

# Verification

- Read the live state before you claim a cause, a fix or a state: the code, `git fetch`,
  the host, the issue. Memory, notes and cached refs go stale.
- Watch each new test fail before the fix. Stash the fix or change the code to prove it.
- Run a final whole-branch review before a merge or a push, after the per-task reviews.

# Shell

- The Bash tool runs zsh. An unquoted `$VAR` does not split into words, and an unquoted
  glob such as `--include=*.ex` fails. Quote globs. Run loops in `bash -c`.
- Keep long command output out of the context. Write an output that can be long (a test
  run, a log, a build, an API reply, a query) to a file in the scratchpad, then read it
  with `head`, `tail` or `grep`. Read the full file only when the parts do not answer.
- Run a slow command (a build, a test suite, a deploy) in an `hc` terminal, so the user
  can watch it with `hc attach`: `hc run --bg --no-notify --name <n> --cwd <dir> -- <cmd>`,
  then `hc wait <n> --timeout 110`. `wait` exits 0: read `exit_code` in its JSON. On
  `reason: timeout`, wait again. Read the end with `hc read <n> | tail -40`, then `hc rm <n>`.
- Put the task or branch name in a run name, for example `shop323-test`, never `fix` or
  `test`. On `name_taken` for a test or a build, pick a new name. Reuse a live terminal
  only for a shared resource.
- Share a dev resource that does not change with the code (a database, a Docker service, a
  docs server) in one `hc` terminal for all agents. Name it after the resource, for example
  `shop-postgres`. Start it:
  `hc run --bg --no-parent --no-notify --name <n> --cwd <dir> -- <cmd>`. On `name_taken`,
  another agent started it: use it, and check its `cwd` and `argv` with `hc get <n>`. Run
  `hc wait <n> --timeout 30`: a live resource ends with `reason: timeout`. Read
  `hc read <n> | tail -40` to see if it is ready. Do not `hc rm` or `hc kill` it: other
  agents use it.
- Agents only read a shared database: a read-only role with a `statement_timeout`, and no
  write credentials in the environment or in a file. The project `CLAUDE.md` has a short
  schema note.
- Each turn reads the whole context again. When you know the next reads (`grep`, `sed -n`,
  `cat`, `git show`), put them in one Bash call or in parallel calls of one turn, not in a
  turn for each read.

# herdr-app

- In herdr-app (`HC_TERMINAL_ID` set), write a terminal address such as `t7` as plain
  text. A Ctrl-click on it peeks at that terminal.
- Write each file path in a reply as a link to the absolute path:
  `[docs/spec.md](file:///home/awea/repo/docs/spec.md)`. Add a line as `#L12`.

# Plugins

## Superpowers

- Write specs and plans under `docs/`, the skill default:
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and
  `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.

