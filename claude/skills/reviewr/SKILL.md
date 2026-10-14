---
name: reviewr
description: Open a herdr-reviewr pane right of this claude pane, for the git worktree of the changes of this session.
argument-hint: "[folder]"
disable-model-invocation: true
allowed-tools: Bash(bash ~/.claude/skills/reviewr/open.sh *)
---

Run this command, with DIR as an absolute path:

```bash
bash ~/.claude/skills/reviewr/open.sh DIR
```

DIR is the first folder that applies:

1. The folder that the user gave: `$ARGUMENTS`.
2. The root of the git worktree where you did the work of this session: edits, commits,
   commands. Use the worktree of your most recent work. This worktree can be different
   from your current folder.
3. Your current folder.

Do not run other commands to find DIR. Use what you know from this session.

Give the user the output of the command in one line. Do nothing more.
