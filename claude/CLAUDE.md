# Workflow

- Always use subagents when possible. Delegate searches, multi-file investigations, and
  broad fixes to subagents (Agent tool) instead of doing them inline. Run independent
  subagents in parallel.
- Set the subagent effort level: `high` for Explore and other search subagents, `low` for
  implementation subagents, `high` for review subagents.

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
- Trust the contract. Do not add guards or fallbacks for inputs that cannot happen:
  `when is_binary(id)` on a plain public function, `when is_map(body)` on an API reply, a
  `with ... else _ -> nil` that hides a malformed value. Let it crash. Keep a guard only
  when it selects between clauses.
- No `try`/`rescue`/`catch` around a call that returns `{:ok, _}` or `{:error, _}`. Use
  `case` on the result and log the `{:error, _}`.
- Use `if` for a boolean, not `case` with `true ->` and `false ->`. Use the block form
  `if ... do ... else ... end` when the keyword form does not fit on one line. The same
  applies to `for` and `def`.
- Do not `case` on a tuple of 2 values (`case {a, b} do`). Use `with`, or 2 steps.
- In a `case`, put the literal clause first (`{:ok, %{email: nil}} ->`) and the general
  clause after it, not a type guard on the general clause. Prefer 1 clause for each
  literal to a `when x in [...]` guard.
- Bind an intermediate value to a variable before a call or a map, instead of a long
  inline expression or an inline `if(...)`.
- Filter first (`Enum.filter`), then act (`Enum.each`). Do not put an `if` inside the
  `Enum.each`.
- Match a known value with a pin in the pattern (`%Session{access_token: ^token}`), not
  with a guard that compares 2 values.
- Join parts with `Enum.join(parts, " ")`, not a chain of `<> " " <>`. Pipe a value into
  a call (`error(...) |> Keyword.update!(...)`) instead of a nested call on many lines.
- Ecto: build the base query once, then add each branch condition with `where/3`. Do not
  write 2 `from` queries that differ in one condition. A query that is a business rule
  becomes a public context function with a `@doc`.
- Oban: return `{:cancel, reason}` for an error that a retry cannot fix, not `:ok`. Use the
  named unique state groups (`:incomplete`) when they match. Keep job options on one line
  when they fit.
- Comments explain why the code is like that. Do not narrate a harmless library log. Do
  not document the code in a migration.
- Tests: name a test after the persona or situation ("a confirmed user stays confirmed
  while the remote service is down"), not after its parameters. Write 1 test for each case,
  not a `for` loop over cases. Put helper `defp`s at the module top, not in a `describe`.
  Use real error names in stub replies, not `"Boom"`. When many tests build the same kind
  of record, add a factory for it.

# Herdr

- In Herdr (`HERDR_ENV=1`), write each Herdr pane or tab ID in a reply as a link:
  `[wQ:p2](https://herdr.invalid/pane/wQ:p2)` or `[wQ:t2](https://herdr.invalid/tab/wQ:t2)`.
  A Ctrl-click on the link focuses that pane or tab (the agent-tabs plugin).
- In Herdr, write each file path in a reply as a link to the absolute path:
  `[docs/spec.md](file:///home/awea/repo/docs/spec.md)`. Add a line as `#L12`. A
  Ctrl-click on the link opens the file in Sublime Text (the agent-tabs plugin).

# Plugins

## Superpowers

- Write specs and plans under `docs/`, the skill default:
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and
  `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.

