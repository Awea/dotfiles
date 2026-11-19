# Lint prose for a file

This part of the ste-writing skill gives the lint steps for prose that goes to a file (docs, commit messages, task trackers), and for a lint that the user asks for. The gate checks chat replies, so a chat reply needs no lint run first: a draft file doubles the output tokens of each reply.

1. Write the draft to a scratch file.
2. Run the linter with the command for the mode (below). Exit code 1 means the score is over the target.
3. Fix the reported categories. Lint one more time. Two passes, no more.
4. Send the text one time.

```
python3 ~/.claude/skills/ste-writing/ste-lint.py --fail-over 2.5 draft.md            # flavored target: under 2.5 per 100 words
python3 ~/.claude/skills/ste-writing/ste-lint.py --strict --fail-over 1.5 draft.md   # strict target: under 1.5 per 100 words
python3 ~/.claude/skills/ste-writing/ste-lint.py --shape --fail-over 2.5 --fail-shape 1 draft.md   # add the Layer 2 counts: over 1 hit fails
```

Done: the last lint run is under the target, or two passes ran and the user has the score that is left. Present text in a file as clean only after that run.

If you cannot run the linter, use [the checklist](~/.claude/skills/ste-writing/checklist.md).
