---
name: using-superpowers
description: The Superpowers rule for skill use. The session-start hook loads it.
disable-model-invocation: true
---

A subagent or a fork with a dispatched task: skip this file and do the task.

## The rule

Before your first action on each user message, check the skill list. A reply, a clarifying question, a file read and a plan are each a first action. Invoke each skill that can apply, even at a small chance. When an invoked skill does not fit, drop it.

The urge to read, ask or act first is the signal to check the list.

Done when each skill that can apply is invoked, or you checked the list and none applies.

User instructions come first: `CLAUDE.md`, `AGENTS.md` and direct requests win over skills, and skills win over default behavior. Skip a skill workflow only when your human partner tells you to.

## After you invoke a skill

1. Announce "Using [skill] to [purpose]".
2. Follow the skill. For a checklist, make one todo per item.

## Order

- Process skills come first: they set the approach. Implementation skills then do the work.
- Before plan mode, invoke brainstorming if you did not brainstorm yet.

## Claude Code

When your human partner asks for a cheaper subagent-driven-development run, read `references/claude-code-tools.md` in the folder of this skill.
