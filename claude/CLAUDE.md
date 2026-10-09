# Workflow

- Always use subagents when possible. Delegate searches, multi-file investigations, and
  broad fixes to subagents (Agent tool) instead of doing them inline. Run independent
  subagents in parallel.

# Git

- Never sign commits. Do not add a `Co-Authored-By` trailer or any signature to commit
  messages.

# Elixir

- Only extract a private sub-function within a module when it is reused by more than one
  function. Otherwise keep the logic inline in the function body using `case`/`if`.

# Herdr

- In Herdr (`HERDR_ENV=1`), write each Herdr pane or tab ID in a reply as a link:
  `[wQ:p2](https://herdr.invalid/pane/wQ:p2)` or `[wQ:t2](https://herdr.invalid/tab/wQ:t2)`.
  A Ctrl-click on the link focuses that pane or tab (the agent-tabs plugin).

# Plugins

## Hunk (interactive diff review)

Hunk's review skill — drive live `hunk` review sessions via the `hunk session *`
CLI. Imported from the nix profile so it tracks the installed hunk version.

@/home/awea/.nix-profile/skills/hunk-review/SKILL.md
