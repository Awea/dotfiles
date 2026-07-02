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

# Plugins

## Hunk (interactive diff review)

Hunk's review skill — drive live `hunk` review sessions via the `hunk session *`
CLI. Imported from the nix profile so it tracks the installed hunk version.

@/home/awea/.nix-profile/skills/hunk-review/SKILL.md
