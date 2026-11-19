# Rewrite or review text

This part of the ste-writing skill gives the two modes for existing text. Layer 1 and Layer 2 of `SKILL.md` apply.

- **rewrite**: convert existing text to STE. Keep every fact.
- **review**: leave the text as it is. Output a table (`Rule | Original | Simplified`), one row for each violation. Then add one line about anything you left alone, and why.

For the two modes:

- Keep every fact, number, condition and scope qualifier, also when a length cap or the five-item cap fails. Keep the longer sentence, and add a note after the text.
- Keep code identifiers, part numbers, units, error strings and safety wording exactly.
- Change the smallest span that fixes a violation. Keep text that no rule touches as it is.
- If the input already complies, return it unchanged and say so.

Done: each violation has a fix (rewrite) or a table row (review).
