# Workflow

- Use a subagent only for independent work that runs in parallel, or for a wide search
  that would put many file dumps into the main context. Do a task of a few tool calls
  inline. Each subagent starts at 20k to 30k tokens before it does any work.
- Use the Explore agent for a search, not general-purpose: it starts at about half the
  tokens.
- Subagents run on Sonnet by default (`CLAUDE_CODE_SUBAGENT_MODEL`). Pass `model: "opus"`
  for Explore and other search subagents.
- Set the subagent effort level: `high` for Explore and other search subagents, `low` for
  implementation subagents.
- Review with the `reviewer` agent type. Its file sets its model, effort and tools.

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

- When the user states a fact, for example "it is rebased", take it as true. Do not
  check it. Check it only when the user asks you to check it.
- Read the live state before you claim a cause, a fix or a state that the user did not
  state: the code, `git fetch`, the host, the issue. Memory, notes and cached refs go
  stale.
- Watch each new test fail before the fix. Stash the fix or change the code to prove it.
- Run a final whole-branch review before a merge or a push, after the per-task reviews.
  Start one `reviewer` on `base..HEAD` with the goal, and fix its findings. This review
  is the final whole-branch review of a superpowers skill: run it once.
- Run the review loop only when the user asks for it. In the loop, fix the findings, then
  send the new commit range to the same reviewer with `SendMessage`. When you reject a
  finding, send the rejected findings with their reasons. Stop when the reviewer writes
  only `no findings`, or after 3 rounds. Report the open findings.
- The reviewer runs in the background, so the loop spans several turns. When the loop
  ends, tell the user to review the branch in herdr reviewr and send the comments from it.
  In herdr-app (`HC_TERMINAL_ID` set), first set two labels on your terminal:
  `hc label "$HC_TERMINAL_ID" reviewr.dir=<worktree root> reviewr.base=<short base SHA>`.
  Then the user presses ctrl+b d on your pane, and reviewr opens on that worktree in the
  branch scope from that base. Set the labels again for each new branch. Outside
  herdr-app, give the short SHA of the base (`git rev-parse --short <base>`): the user
  presses `b` for the branch scope, then presses `B`, types the short SHA of the base commit
  and picks the row it adds. A branch name such as `master` resolves to `origin/master`, so
  it also shows the unpushed commits.
- In Renux (`REX_BLOCK` set and `HC_TERMINAL_ID` not set), in place of the `hc label` step
  and of the `b`/`B` steps, run
  `~/.config/rex/bin/reviewr-target <worktree root> <short base SHA>`. Then the user
  presses ctrl+b d on your pane, and reviewr opens on that worktree and base. Run it
  again for each new branch.
- Run the Fable review only when the user asks for it. Offer it in the last message of the
  branch. For it, start a new `reviewer` with `model: "fable"` on `base..HEAD`, and fix its
  findings.

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
- Put `~/.bin/when-free` before the command of a build or a test suite:
  `hc run ... -- ~/.bin/when-free mix test`. It waits until the CPU load and the free RAM
  let the command start, for all agents of all boards. Its lines in the terminal tell why
  it waits. A long wait is not an error: wait again. It runs one program: for env vars
  write `when-free env MIX_ENV=test mix test`, for a shell line `when-free bash -c '...'`.
- Put the task or branch name in a run name, for example `tokup323-test`, never `fix` or
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

## Rex

- In Renux (`REX_BLOCK` set and `HC_TERMINAL_ID` not set), use these rules in place of the `hc` rules above.
- Run a slow command (a build, a test suite, a deploy) in a tab the user can watch:
  `rex run -s "$REX_SESSION" --focus=false --keep-open --interactive --label <n> --cwd <dir> --json -- ~/.bin/when-free <cmd>`.
  It prints `{window_id, block_ids:[…]}`. Keep the block ID and use it, not the label:
  Rex does not refuse a second tab with the same label. Put the task or branch name in
  the label, for example `tokup323-test`, never `fix` or `test`.
- Wait with `rex wait <block> --for 110s --json`. It gives the exit status of the command.
  The end of the command prints `{"exit_code":N,…}`. A time-out prints no JSON: it gives
  the error "wait timed out" and exit 1. On a time-out, wait again.
- Read the end with `rex capture -b <block> --trim | tail -40`, then close the tab with
  `rex block close <block>`.
- Start a shared resource once for all agents with `~/.bin/rex-resource <n> <dir> -- <cmd>`.
  Its JSON tells the block, the session, `started`, `cwd` and `argv`: check `cwd` and
  `argv` when `started` is false. Read it with
  `rex capture -s <session> -b <block> --trim | tail -40`. Do not close a shared resource.

# Live data

- To read live data, run `board-ro list`. It shows the databases and the notebooks folder
  of the board of the current folder.
- Run a read-only SQL query with `board-ro sql <db> "<query>"`. Write long output to a file.
- Run a read-only query without asking the user: SQL, an MCP read, an API read. Ask first
  only when the query is expensive, for example a full scan of a big table.
- Use the board MCP servers (for example Cloudflare, AppSignal) for the other live data.
- When you explore an idea on live data, run `board-ro notebook <topic>`. Write the
  queries and the result in that notebook, then commit it in the notebooks folder.

# herdr-app

- In herdr-app (`HC_TERMINAL_ID` set), write a terminal address such as `t7` as plain
  text. A Ctrl-click on it peeks at that terminal.
- In Renux (`REX_BLOCK` set and `HC_TERMINAL_ID` not set), write the tab name of a job,
  not a `t7` address.
- Write each file path in a reply as a link to the absolute path:
  `[docs/spec.md](file:///home/awea/repo/docs/spec.md)`. Add a line as `#L12`.

# Plugins

## Superpowers

- Write specs and plans under `docs/`, the skill default:
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and
  `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.

