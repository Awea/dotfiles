---
name: reviewr
description: Open a herdr-reviewr pane right of this claude pane, for the git worktree of the changes of this session.
argument-hint: "[folder]"
disable-model-invocation: true
allowed-tools: Bash(bash ~/.claude/skills/reviewr/open.sh *)
---

The command below opened reviewr, or it gave the cause of the failure:

!`bash ~/.claude/skills/reviewr/open.sh "$ARGUMENTS"`

Give the user this result in one line. Do nothing more.
