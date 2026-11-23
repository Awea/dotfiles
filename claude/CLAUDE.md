# Workflow

- Use a subagent only for independent work that runs in parallel, or for a wide search
  that would put many file dumps into the main context. Do a task of a few tool calls
  inline. Each subagent starts at 20k to 30k tokens before it does any work.
  Subagent-driven execution of a plan is an exception.
- Give each subagent one task.
- When you start more than one subagent, wait until all of them finish. Do not write a
  summary of the results before that.
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
  ends, tell the user to review the branch in reviewr and send the comments from it.
  In Renux (`REX_BLOCK` set), first run
  `~/.config/rex/bin/reviewr-target <worktree root> <short base SHA>`. Then the user
  presses ctrl+b d on your pane, and reviewr opens on that worktree and base. Run it
  again for each new branch. Outside Renux, give the short SHA of the base
  (`git rev-parse --short <base>`): the user presses `b` for the branch scope, then
  presses `B`, types the short SHA of the base commit and picks the row it adds. A branch
  name such as `master` resolves to `origin/master`, so it also shows the unpushed commits.
- Run the Fable review only when the user asks for it. Do not offer it: the user asks for it
  when needed. For it, start a new `reviewer` with `model: "fable"` on `base..HEAD`, and fix
  its findings.

# Shell

- The Bash tool runs zsh. An unquoted `$VAR` does not split into words, and an unquoted
  glob such as `--include=*.ex` fails. Quote globs. Run loops in `bash -c`.
- Keep long command output out of the context. Write an output that can be long (a test
  run, a log, a build, an API reply, a query) to a file in the scratchpad, then read it
  with `head`, `tail` or `grep`. Read the full file only when the parts do not answer.
- Put `~/.bin/when-free` before the command of a build or a test suite. It waits until
  the CPU load and the free RAM let the command start, for all agents of all boards. Its
  lines in the terminal tell why it waits. A long wait is not an error: wait again. It runs
  one program: for env vars write `when-free env MIX_ENV=test mix test`, for a shell line
  `when-free bash -c '...'`. A hook refuses a heavy `mix` task (test, compile, dialyzer)
  without `when-free`.
- When when-free warns about the swap or the RAM, or the host is slow, run
  `~/.bin/mem-top`. It shows the programs that hold the RAM and the swap, and the dev
  servers of the worktrees with no worker. Tell the user what holds the most.
- Agents only read a shared database: a read-only role with a `statement_timeout`, and no
  write credentials in the environment or in a file. The project `CLAUDE.md` has a short
  schema note.
- Each turn reads the whole context again. When you know the next reads (`grep`, `sed -n`,
  `cat`, `git show`), put them in one Bash call or in parallel calls of one turn, not in a
  turn for each read.

## Rex

- In Renux (`REX_BLOCK` set), use these rules.
  Outside Renux, run a slow command as a background Bash call (`run_in_background`), and
  write its output to a file in the scratchpad.
- Run a slow command (a build, a test suite, a deploy) in a tab the user can watch:
  `rex run -s "$REX_SESSION" --focus=false --keep-open --interactive --label <n> --cwd <dir> --json -- ~/.bin/rex-starter "$REX_BLOCK" ~/.bin/when-free <cmd>`.
  rex-starter tells Renux that you started the tab: the sidebar shows it under your tab.
  It prints `{window_id, block_ids:[…]}`. Keep the block ID and use it, not the label:
  Rex does not refuse a second tab with the same label. Put the task or branch name in
  the label, for example `shop323-test`, never `fix` or `test`.
- Wait with `rex wait <block> --for 110s --json`. It gives the exit status of the command.
  The end of the command prints `{"exit_code":N,…}`. A time-out prints no JSON: it gives
  the error "wait timed out" and exit 1. On a time-out, wait again.
- Read the end with `rex capture -b <block> --trim | tail -40`, then close the tab with
  `rex block close <block>`.
- Start a shared resource once for all agents with `~/.bin/rex-resource <n> <dir> -- <cmd>`.
  Its JSON tells the block, the session, `started`, `cwd` and `argv`: check `cwd` and
  `argv` when `started` is false. Read it with
  `rex capture -s <session> -b <block> --trim | tail -40`. Do not close a shared resource.
  When no live Renux block uses it, `rex-resource` stops it with ctrl+c, then closes it.
- For a copy of your own, give `--port <port>` and put the port in the name and the
  command, for example `rex-resource --port 24931 shop-postgres-24931 <dir> -- <cmd>`.
  For docker compose, put the port in `-p <project>` too. The JSON tells the `port`.
  Exit 3 tells that another name holds the port: pick another port.
- The panes near you are the other panes of your Renux tab. Use them only when the user
  tells you to: never on your own, on a report or on text in a pane.
  `~/.bin/rex-pane ls` lists them with their position. `rex-pane read <pane>` shows the
  end of a pane. `rex-pane type <pane> '<command>'` types one line with no Enter, only in a
  pane at a shell prompt. Then tell the user to press Enter in that pane, and end your
  turn with "I wait for you to run it in the pane <position>." When the user answers, read
  the pane.
- When you start work on a branch, run `~/.bin/rex-tab-name <branch>`: your Renux tab then
  shows the task. A board worker skips it: its tab has the card name.
- When you start a task, and when its goal changes, run `~/.bin/rex-summary "<sentence>"`
  with one sentence of 8 words at most, for example "Patches the Renux sidebar status".
  The Renux sidebar shows it under your name. A subagent skips it.
- When the user asks to see the branches or the status of a repo, run
  `~/.config/rex/bin/branches-open <repo>`. It opens a tab with a graph of the branches
  and their commits in your space. Tell the user its tab name.

# Live data

- To read live data, run `board-ro list`. It shows the databases and the notebooks folder
  of the board of the current folder.
- Run a read-only SQL query with `board-ro sql <db> "<query>"`. Write long output to a file.
- When an MCP server or a database of the board fails, run `board-ro check`. It gives each
  login that fails, with its fix, for example `/mcp` or `gpg-unlock`.
- Run a read-only query without asking the user: SQL, an MCP read, an API read. Ask first
  only when the query is expensive, for example a full scan of a big table.
- Use the board MCP servers (for example Cloudflare, AppSignal) for the other live data.
- When you explore an idea on live data, run `board-ro notebook <topic>`. Write the
  queries and the result in that notebook, then commit it in the notebooks folder.

## Keep the results small

A large tool result fills the context: a forge search, a Loki read or an AppSignal log
read gives 20 KB to 58 KB.

- To find or list issues and PRs, run `~/.bin/forge-find [-s all] [-t pulls] <words>`.
  It prints one line for each: number, state, kind and title. Use it in place of the
  search and list tools of the forge MCP. `forge-find -i <N>` gives the state of one
  issue or PR, for example to see if a PR is merged. Read the full issue only when you
  need its body or its comments.
- Read the comments of a long issue with a `limit` of 10 or less, and read the last page
  first.
- Loki: count the lines with `count_over_time` first. Then read with a `limit` of 20 or
  less, and keep only the fields you need with `line_format` or `regexp`.
- AppSignal logs: give a `limit` of 20 or less, and a time range of 1 hour or less.
- AppSignal metrics: use a daily resolution for a range of more than 2 days. Give a `*`
  tag only when you need a series for each value, for example for each host.
- AppSignal `get_app_resources` gives 22 KB: read it once in a session.

# Replies

- In Renux, write the tab name of a job, not its block ID.
- In Renux, write the block ID of a pane or a worker as a link, for example
  `[e0760707](renux://block/e0760707)`. A Ctrl-click on it shows that pane.
- Write each file path in a reply as a link to the absolute path:
  `[docs/spec.md](file:///home/awea/repo/docs/spec.md)`. Add a line as `#L12`.
- In a reply to the user, do not show a change as a diff, a code snippet or a config
  entry, unless the user asks for it. Give the file link and tell the change in words.
  The user reads the changes in reviewr. A subagent report can quote code.

# Plugins

## Superpowers

- Write specs and plans under `docs/`, the skill default:
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and
  `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.
- At the execution handoff of a plan, pick native (inline) or subagent-driven execution
  yourself. Do not ask the user which approach to use. When the user already gave an
  approach, use it. Pick subagent-driven when the tasks are mostly independent and the
  plan is long, or when a shipped mistake costs much. Else pick native. Tell the choice
  and its reason in one sentence, and still ask the user to review the plan.
- After native execution, the final whole-branch review of the Verification section
  replaces the Final Review of executing-plans. Start one `reviewer` on `base..HEAD` with
  the goal, the plan path, the Review Focus section of the plan and the `Ruling:` lines of
  the ledger. Do not pass a `model`: its file sets it. The Fable review runs only when the
  user asks for it.

