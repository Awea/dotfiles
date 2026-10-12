# Workflow

- Always use subagents when possible. Delegate searches, multi-file investigations, and
  broad fixes to subagents (Agent tool) instead of doing them inline. Run independent
  subagents in parallel.
- Set the subagent effort level: `medium` for Explore and other search subagents, `high` for
  implementation and review subagents.

# Git

- Never add a signature to commit messages: no `Co-Authored-By` trailer and no
  generated-by line. GPG signing stays on.
- Before the first commit of a session, test the gpg-agent cache:
  `echo test | gpg --batch --pinentry-mode error --clearsign >/dev/null`. When it fails,
  ask the user to run `gpg-unlock`. Never use `--no-gpg-sign`.
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

# Elixir

- Only extract a private sub-function within a module when it is reused by more than one
  function. Otherwise keep the logic inline in the function body using `case`/`if`.
  Exception: when credo `Refactor.Nesting` or `Refactor.CyclomaticComplexity` fails, first
  flatten with `with`. Split into a single-use private function only when `with` does not fix it.
- Normalize an input once, then `case` on the normalized value. Don't spread literal-value
  clauses across function heads while a catch-all does the normalizing — the literal heads
  then only fire for already-normalized inputs and variants take the wrong branch.

# Herdr

- In Herdr (`HERDR_ENV=1`), write each Herdr pane or tab ID in a reply as a link:
  `[wQ:p2](https://herdr.invalid/pane/wQ:p2)` or `[wQ:t2](https://herdr.invalid/tab/wQ:t2)`.
  A Ctrl-click on the link focuses that pane or tab (the agent-tabs plugin).

# Plugins

## Superpowers

- Write specs and plans under `docs/`, the skill default:
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and
  `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.

