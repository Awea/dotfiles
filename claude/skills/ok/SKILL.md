---
name: ok
description: Close this board worker when no work is left. Check the report, git, the PR and the open questions first.
disable-model-invocation: true
allowed-tools: Bash(bash ~/.claude/skills/board-orchestrator/dispatch.sh left)
---

The user typed `/ok`: the user thinks that the work of this board worker is finished.
Check that no work is left, then ask the orchestrator to close this worker. Do not do the
remaining work: do not rebase, push or merge.

1. Run `echo "$BOARD_ROLE"`. When it is not `worker`, write
   "/ok works only in a board worker." and stop.
2. Make the report current. Your first prompt gives the report path and the command that
   sends it. When there is no report, or the work changed after the last report (a
   commit, a push, a PR, an answer of the user), write the full report again and send it.
3. Run `bash ~/.claude/skills/board-orchestrator/dispatch.sh left`. Exit 0: git has no
   left work. Exit 3: each line is a left thing. Another exit: tell the user the error
   and stop.
   - `uncommitted: <worktree>`: changes that are not committed.
   - `branch: <branch> of <repo>` or `detached: <worktree>`: commits that the default
     branch does not have. When the forge shows the PR of that branch as merged (a
     squash merge), it is not left.
   - `report: none`: step 2 failed. It is left.
4. Check each PR of this work on the forge. An open PR is left, except in two cases:
   - The report starts with `RESULT: WAITS FOR USER`. The card then stays open.
   - The report has a follow-up task for that PR under `## Vault changes`.
5. Check this conversation. These are left:
   - a question to the user that has no answer
   - a background command, a job or a reviewer agent that still runs
6. When nothing is left, run the close command of your first prompt, exactly as it is
   written there ("When the user tells you to close, run: ..."). Its allow rule has that
   exact form. Then end your turn with no text.
7. When something is left, write one line for each left thing. Then end your turn with
   this question alone on its last line: Close anyway?
   - On a yes, run the close command of step 6 and end your turn.
   - On another answer, do what the user says. Do not close.
