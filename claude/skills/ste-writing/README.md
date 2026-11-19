# ste-writing

The ste-writing skill sets the style of all prose that a human reads. Layer 1 is ASD-STE100
Simplified Technical English (Issue 9, January 2025). Layer 2 is the shape of a reply for a
reader with ADHD. This README is for a human. The agent reads `SKILL.md`, and `lint.md` or
`review.md` when `SKILL.md` sends it there.

Source: the ep01 kit of
[woosal1337/blog](https://github.com/woosal1337/blog/tree/main/videos/ep01-the-cure-for-ai-slop).
The full standard is free at https://asd-ste100.org.

## Files

| File | Use |
|---|---|
| `SKILL.md` | The rules of the two layers. |
| `lint.md` | The lint steps for prose in a file. |
| `review.md` | The rewrite and review modes. |
| `checklist.md` | The checks to do by hand when the linter cannot run. |
| `ste-recurring-errors.md` | The 39 most frequent writer errors of the standard. |
| `ste-lint.py` | The linter. `--strict`, `--shape`, `--json`, `--fail-over N`. |
| `hooks/ste-inject.sh` | SessionStart and UserPromptSubmit hook: the rule card and the gate feedback. |
| `hooks/ste-gate.py` | Stop hook: lints each chat reply. |
| `tests/` | The pytest tests of the linter and the hooks. |

## The gate and the hooks

- `ste-gate.py` lints each chat reply after the model sends it, at no token cost. It warns
  over 2.5 violations per 100 words, and blocks only over 4.0. A block makes the model send
  the reply a second time, so a lint of a draft before each reply only doubles the output.
- `ste-inject.sh` sends a short rule card at session start. On a later prompt, it sends the
  card again only after a reply over the target, with the score of that reply.
- A repo with its own `.claude/skills/ste/hooks` gives its own card, and the global hooks
  stay silent.

## Rule numbers of the standard

| Rule | Number |
|---|---|
| One name for one thing | 1.11, 9.4 |
| One meaning for each word | 1.3 ("fall" means to move down, not to decrease) |
| Noun clusters of three words at most | 2.1 |
| Simple tenses | 3.2 |
| Past participle as an adjective | 3.3 |
| No stacked auxiliaries | 3.4 |
| No "-ing" main verb where a simple tense works | 3.5 |
| Active voice | 3.6 |
| A verb for an action | 3.7 |
| Keep the words, no telegraph style | 4.2 |
| Plain connectors | 4.4 |
| Articles and demonstratives | 4.5 |
| At most 20 words for an instruction | 5.1 |
| One instruction for each sentence | 5.2 |
| A comma after a condition | 5.4 |
| At most 25 words for descriptive text | 6.3 |
| One topic for each paragraph, six sentences at most | 6.5, 6.6 |
| WARNING, CAUTION, NOTE | 7.1 to 7.3, 5.5 |
| No semicolons | 8.1 |
| No phrasal verbs | 9.3 |

## Word lists

- Short common words: start (for begin, commence, initiate), use (utilize, leverage), help
  (facilitate), make sure (ensure, verify), do (perform, conduct), give or supply
  (provide), before (prior to), after (subsequent to), about (regarding, concerning), get
  (obtain, acquire), show (demonstrate), also (additionally, furthermore, moreover).
- Marketing adjectives: seamless, robust, powerful, cutting-edge, effortless, world-class,
  next-generation, revolutionary, elegant.
- Phrasal verbs: spin up, dive into, kick off, roll out, reach out.
- Articles: do not add one to a general statement ("Solvents can cause damage to paint").
  In a series, the article before the first noun is enough.
- STE-flavored mode relaxes the 875-word dictionary and the strict word set, so that the
  text keeps enough range to read naturally.

## Why Layer 2 is so

Four facts about the reader drive the rules:

1. Working memory is small. A fact off the screen is gone.
2. To know the answer is not to do the answer. Work stops between "got it" and "done it".
3. The start is the hardest step. The first action must be obvious, small and doable now.
4. Visible progress counts. A buried win does not register.

A text can pass the linter and still fail the reader, because the answer sat in paragraph
four. Layer 1 makes a sentence readable. Layer 2 makes a reply usable.

## Examples

| Rule | Bad | Good |
|---|---|---|
| Lead with the action | "Let us think about this. Your auth flow has a few moving pieces..." | "Run `npm install jsonwebtoken`, then edit `src/auth.ts:42`." |
| Number the steps | "First open the file, find the function, swap it out, then run the tests." | "1. Open `src/auth.ts` 2. Replace `verifyToken` (lines 42 to 58) 3. Run `npm test -- auth.spec.ts`" |
| End with one action | "Hope that helps. Tell me if you want to go deeper." | "Next: run `npm test` and paste the first failing line." |
| One issue at a time | "Here is the fix. By the way, your dependency is stale, and..." | "Here is the fix. Separately: the dependency is stale. Do you want that next?" |
| State the step | "Done. Ready for the next part?" | "Step 3 of 5 done: the schema is updated. Next: backfill the new column." |
| An error | "Uh oh, the test is failing. There seems to be an issue..." | "`auth.spec.ts:42` fails: expected 200, got 401. Cause: the auth header is missing." |

`SKILL.md` keeps only the good forms of these examples: a quoted bad phrase in the agent
text makes that phrase more likely.

## Tests

`python3 -m pytest claude/skills/ste-writing/tests`.
