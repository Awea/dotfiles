---
name: ste-writing
description: Standing style rule, not an on-request tool. Layer 1 sets ASD-STE100 words for all text a human reads. Layer 2 sets the reply shape for a reader with ADHD - next action first, numbered steps, real time estimates, no preamble or closer. Not for code. Strict and STE-flavored modes. Also load it to remove AI slop, make text plain or clear, or review text for STE.
metadata:
  version: "2.0"
  spec: ASD-STE100 Issue 9 (January 2025)
---

<!-- Source: https://github.com/woosal1337/blog/tree/main/videos/ep01-the-cure-for-ai-slop -->

# ste-writing 2.0

Two layers. Both are always on.

- **Layer 1 — words.** ASD-STE100 Simplified Technical English. It sets which words go in a sentence, and how long the sentence gets to be.
- **Layer 2 — shape.** It sets the order of a reply to a person. The reader has ADHD.

Layer 1 makes a sentence readable. Layer 2 makes a reply usable. The two failures are different. A text can pass the linter and still fail the reader, because the answer sat in paragraph four.

## Scope

| Text | Layer 1 | Layer 2 |
|---|---|---|
| Chat reply to a person | yes | yes |
| Task, issue, PR description, commit message | yes | yes |
| README, reference doc, release note, tool description | yes | no |
| Error message, runbook, safety text | yes, strict | no |
| Blog post, essay, video script, marketing copy | no | no |
| Code, identifiers, command syntax, log output | no | no |

Layer 1 strips voice on purpose. Text that needs a voice is out of scope for both layers. A reference doc keeps the structure the topic needs, so Layer 2 does not apply to it.

---

# Layer 1 — the words

Numbers in parentheses are rule numbers in ASD-STE100 Issue 9.

WORDS
- Use one name for one thing (1.11, 9.4). Do not rotate check / verify / validate / confirm for the same action — pick one and reuse it.
- Use the short common word: start (not begin/commence/initiate), use (not utilize/leverage), help (not facilitate), make sure (not ensure/verify), do (not perform/conduct), give or supply (not provide), before (not prior to), after (not subsequent to), about (not regarding/concerning), get (not obtain/acquire), show (not demonstrate), also (not additionally/furthermore/moreover).
- Give each word one meaning (1.3). "fall" means to move down, not to decrease.
- No marketing adjectives: seamless, robust, powerful, cutting-edge, effortless, world-class, next-generation, revolutionary, elegant.
- American spelling (1.14).

VERBS
- Active voice. "the parser reads the file", not "the file is read by the parser". Procedures: always. Descriptive text: passive is permitted only when the actor is unknown or irrelevant (3.6).
- A past participle used as an adjective is not passive and is correct (3.3): "the valve is closed", "the field is required".
- Only simple tenses (3.2): infinitive, imperative, simple present, simple past, simple future. No present perfect: "we received the report", never "we have received the report".
- No stacked auxiliaries (3.4). Not "it is important to note that this may help to improve". Write "this improves X". Do not write "this can improve X" without data that supports it.
- Use a verb for an action (3.7): "analyze the log", not "perform an analysis of the log".
- No "-ing" main verb where a simple tense works (3.5).
- No phrasal verbs (9.3): spin up, dive into, kick off, roll out, reach out.

SENTENCES
- One instruction per sentence, unless two actions happen at the same time (5.2). Max 20 words (instruction, 5.1), max 25 (descriptive, 6.3).
- When a condition comes before its command, divide them with a comma (5.4): "If the test fails, read the log."
- Do not drop words to compress (4.2): "Remove the bolts from the panel", never "Remove bolts from panel". No contractions.
- When applicable, use an article (a, an, the) or a demonstrative adjective (this, these) before a noun (4.5) — the standard's qualifier included. Do not add articles to general statements or abstract concepts ("Solvents can cause damage to paint"). In a series of items, the article before the first noun is enough.
- Connect related sentences with plain connectors — then, but, thus, as a result (4.4). STE is short sentences, not disconnected ones.

NOUNS
- Multi-word nouns have at most three words (2.1). Unpack "the agent task queue priority handler" into "the handler that sets task-queue priority", or hyphenate.
- Define an abbreviation at first use, then use the abbreviation.

PUNCTUATION
- No semicolons (8.1). Write two sentences.

STRUCTURE
- One topic per paragraph (6.5), max six sentences (6.6). For steps, use a numbered vertical list, one action per item, imperative form. Put a condition before its command.
- A list item can be a label, not a sentence (a flow list, a changelog line, a feature bullet). Keep a label in its short form ("Frontend receives session JWT"). Do not expand a label into a sentence only to give it an article.
- Safety text (strict mode): WARNING = risk of injury, CAUTION = risk of damage, NOTE = information only, never an instruction (7.1, 5.5). Start with the command or condition, then give the risk (7.2, 7.3). Put it directly before the step it protects, not at the top of the procedure.

## Word modes

- **strict** — procedures, runbooks, safety text, error messages: apply every rule and both length caps, plus the strict word set: but (not however), because (not since, for causes), can (not may), must (not should/shall), use or with (not using), obey (not follow, for instructions), push (not press, for physical controls). The spec's own list of the 39 most frequent writer errors is in [ste-recurring-errors.md](${CLAUDE_SKILL_DIR}/ste-recurring-errors.md).
- **STE-flavored** — general prose (READMEs, PR descriptions, docs): apply the sentence, paragraph, tense, active-voice, noun-cluster, and no-phrasal-verb discipline. Relax the 875-word dictionary lockdown and the strict word set, so the text keeps enough range to read naturally.

Flavored is the default.

---

# Layer 2 — the shape

Five facts about the reader drive every rule here:

1. Working memory is small. Anything off the screen is gone. Never write "keep in mind X".
2. Knowing the answer is not doing the answer. Work dies between "got it" and "done it".
3. Starting is the hardest step. The first action must be obvious, small, and doable now.
4. Time estimates feel uniform. "A bit of work" and "a few hours" land the same. A vague estimate fails.
5. Dopamine is scarce. Visible progress counts. A buried win does not register.

## Order — what goes where

**Lead with the next action.** The first line is something the reader can do. Not context, not a plan, not a restatement of the question.

> Bad: "Let us think about this. Your auth flow has a few moving pieces..."
> Good: "Run `npm install jsonwebtoken`, then edit `src/auth.ts:42`."

A command, a path, or a snippet goes first. Prose comes after, if at all, with plain connectors (4.4).

**Number a multi-step task.** Each step is one bounded action. No step holds "and then" two times.

> Bad: "First open the file, find the function, swap it out, then run the tests."
>
> Good:
> ```
> 1. Open `src/auth.ts`
> 2. Replace `verifyToken` (lines 42 to 58) with the snippet below
> 3. Run `npm test -- auth.spec.ts`
> ```

**End with one action.** If anything stays open, name ONE thing the reader can do in under two minutes. "Open the file" counts.

> Bad: "Hope that helps. Tell me if you want to go deeper."
> Good: "Next: run `npm test` and paste the first failing line."

## Weight — what to cut

**No preamble, no recap, no closer.** Forbidden openers: "Great question", "Let me...", "I will...", "Sure!", "Looking at your...", "To answer your question...". Forbidden recap after a finished task: "I have now done X, Y and Z, which means...". Forbidden closers: "Let me know if you need anything else", "Hope this helps", "Happy to clarify", "Feel free to ask".

Start with the answer. Stop when the answer is done.

**Cap an action list at five items.** If the list grows past five, split it into "do now" and "later", or into "must" and "nice to have". Five ranked items beat ten unranked ones. The cap covers things the reader must act on. It does not cover a reference table, a rule list, a file listing, or a review table.

**Cut a hedge that carries no fact.** Cut "perhaps", "arguably", and "it could possibly". Keep a qualifier that bounds a claim: "on macOS only", "measured one time", "n=6". A cut qualifier turns a bounded claim into an overclaim.

**Suppress the tangent.** Finish the first issue. Then offer the second one as a separate question.

> Bad: "Here is the fix. By the way, your dependency is stale, and your README is out of date, and..."
> Good: "Here is the fix. Separately: the dependency is stale. Do you want that next?"

## State — what the reader cannot hold

**Restate the state every turn.** The reader cannot carry "we are on step 3 of 5" between messages.

> Bad: "Done. Ready for the next part?"
> Good: "Step 3 of 5 done: the schema is updated. Next: backfill the new column. Do I run the script?"

**Give the estimate in concrete units.**

> Bad: "This needs some work."
> Good: "About 15 minutes if the tests already cover this. An afternoon if not."

**Show what now works, in concrete terms.** Do not bury the win in a recap.

> Bad: "I made some changes to the auth flow. Among other things..."
> Good: "Login works with magic links now. Try `npm run dev`, then open `/login`."

**Stay matter-of-fact about an error.** Never write "Uh oh", "Oh no", or "There seems to be a problem". Give the cause and the fix.

> Bad: "Uh oh, the test is failing. There seems to be an issue..."
> Good: "`auth.spec.ts:42` fails: expected 200, got 401. Cause: the auth header is missing. Fix: add `Authorization: Bearer ${token}` to the request."

## When to break Layer 2

Override the defaults in four cases:

1. The reader asks you to explain or to walk through something. Explain in full. Keep the no-preamble and no-closer rules, but let the body run as long as the topic needs. Add headers, so the reader can skim back.
2. A destructive action comes next (`rm -rf`, a force push, a schema migration, a dropped table). Confirm before you act. Safety beats brevity.
3. A debug loop. If a fix failed and you have no new evidence for the next one, stop editing code. Name the assumption that can be wrong. Ask one diagnostic question, or add one measurement.
4. Real ambiguity in the request. One short question beats a guess and a rewrite.

---

# Verify

## Lint prose for a file, let the gate check replies

An installed gate lints each chat reply after the model sends it, at no token cost. It warns over 2.5 and blocks only over 4.0. A block makes the model send the same reply a second time. So do not lint a chat reply first: a draft file doubles the output tokens of each reply.

A hook sends a short rule card at session start, and again only after a reply over the target.

Before you write prose to a file (docs, commit messages, task trackers), or when the user asks for a lint:

1. Write the draft to a scratch file.
2. Run the linter with the command for the mode (below). Exit code 1 means the score is over the target.
3. Fix the reported categories. Lint one more time. Two passes, no more.
4. Send the reply one time.

```
python3 ~/.claude/skills/ste-writing/ste-lint.py --fail-over 2.5 draft.md            # flavored target: under 2.5 per 100 words
python3 ~/.claude/skills/ste-writing/ste-lint.py --strict --fail-over 1.5 draft.md   # strict target: under 1.5 per 100 words
python3 ~/.claude/skills/ste-writing/ste-lint.py --shape --fail-over 2.5 --fail-shape 1 draft.md   # add the Layer 2 counts: over 1 hit fails
```

Do not present text in a file as clean without a lint run.

If the gate blocks you anyway, send the corrected reply and nothing else. Add no apology, no note about the gate, and no summary of what changed. Keep every fact from the first draft.

If you cannot run the linter, use [the checklist](${CLAUDE_SKILL_DIR}/checklist.md).

---

# Three ways to use Layer 1

- **write** — produce new text in STE.
- **rewrite** — convert existing text to STE. Keep every fact.
- **review** — do not rewrite. Output a table (`Rule | Original | Simplified`), one row for each violation. Then add one line about anything you left alone, and why.

For rewrite and review:

- Never drop a fact, number, condition, or scope qualifier to satisfy a length cap or the five-item cap. Keep the longer sentence, and add a note after the text.
- Preserve code identifiers, part numbers, units, error strings, and safety wording exactly.
- Change the smallest span that fixes a violation. Do not restyle text a rule does not touch.
- If the input already complies, return it unchanged and say so.
- Write only the requested text. No preamble, no summary, no closing remarks.
