---
name: project-tool-check
description: Check the tools of a project before agents work in it, so that each production action is an explicit command.
argument-hint: "Repo path (default: the current repo)"
disable-model-invocation: true
---

Safety comes from the tools. A well-built tool reaches production only when someone asks for it by name. This check finds each tool that reaches production, money or real data, and makes it **explicit**: its own command, a name that says what it touches, and the target given on the command line. The tool shape is the whole protection: the result is tool fixes and docs.

Read the repo only. Run no script, target or CLI of the repo during the check.

## Steps

1. **List the entry points**: each way to run something in the repo. Makefile or justfile targets, `bin/` and `scripts/`, package scripts and mix aliases, env files that people source, `.envrc`, git hooks, compose files, CI workflows. Done: each file in these places is in the list.

2. **Trace the blast radius** of each entry point. Follow each call: sourced files, sub-scripts, make prerequisites, default values of env variables, and the arguments that a sourced file sees (it sees the arguments of its caller). Note where the entry point reaches (local, a shared service, production) and what it does there (read, write, delete, deploy, spend money, read secrets). Done: each entry has a reach and an action, each with the file and line that prove it.

3. **Mark the side effects.** A side effect is a production action that a command for other work starts: a test run, a setup, a seed, a lint, the sourcing of an env file. Frequent shapes:
   - a sourced file that acts when it gets an argument,
   - a fallback value that points at production,
   - a setup or test target that loads live secrets or calls a live API,
   - output sent to a file, which hides what happened.

   Done: each production path from step 2 is explicit or marked as a side effect.

4. **Design the fix** for each side effect. The target shape:
   - Each production action is its own command, and its name says so (`bin/deploy`, `bin/push-prod-config`).
   - The command takes the target as an argument (`bin/deploy shop-prod`) and prints what it does.
   - Env files hold data only. Local and test commands load local or test values only.
   - Defaults point at local.

   An explicit production command with an explicit target already has the target shape. Keep it as it is, so that an agent can run it when the user names it. Done: each side effect has a fix in this shape.

5. **Write the result.**
   - README: a section "Production commands", one line for each explicit production command and what it touches. Correct each README line that describes a command wrongly.
   - The repo `CLAUDE.md` (or `AGENTS.md`): one line, "The commands that act on production are in README.md, section Production commands. Run one when the user names it."
   - The fixes from step 4: on a branch, as a PR when the user agrees.
   - The project note in the vault: the date, the production commands, the side effects found and the PR link. Under the board orchestrator, put this text in the report as a vault change.

   Done: the user has the side effects with file and line, the PR link and the doc text.
