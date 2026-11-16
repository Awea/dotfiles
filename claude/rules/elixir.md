---
paths:
  - "**/*.{ex,exs,heex}"
---

# Elixir

- Only extract a private sub-function within a module when it is reused by more than one
  function. Otherwise keep the logic inline in the function body using `case`/`if`.
  Exception: when credo `Refactor.Nesting` or `Refactor.CyclomaticComplexity` fails, first
  flatten with `with`. Split into a single-use private function only when `with` does not fix it.
- Normalize an input once, then `case` on the normalized value. Don't spread literal-value
  clauses across function heads while a catch-all does the normalizing — the literal heads
  then only fire for already-normalized inputs and variants take the wrong branch.
- Select the behavior with a function head on a literal option that needs no normalizing
  (`call(resolution, :confirmed_email)`, then `call(resolution, _config)`), not with a
  boolean trick in one body (`config != :confirmed_email or ...`).
- Put a check that 2 callers share in a public context function that returns `:ok` or
  `{:error, reason}` (`ensure_email_confirmed/2`). Callers use `:ok <- ...` in their `with`.
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
- Use `and`, `or` and `not` for boolean logic. They need a boolean on the left side, also
  in a `with` clause (`true <- trusted_host?(host) or {:error, :untrusted_host}`). Keep `||`
  and `&&` for flow control on a value that can be nil, such as a default or a fallback
  (`Repo.get(Session, id) || {:error, :not_found}`).
- Keep each `with` clause short. Bind the result to a name (`{:ok, file} <- ...`) and
  destructure it in the body, not with a large pattern on many lines in the clause.
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
