---
name: ste-writing
description: ASD-STE100 words for all prose a human reads, and the reply shape for a reader with ADHD. Load it to write, rewrite or review text in STE, or to remove AI slop.
metadata:
  spec: ASD-STE100 Issue 9 (January 2025)
---

<!-- Source: https://github.com/woosal1337/blog/tree/main/videos/ep01-the-cure-for-ai-slop. The README gives the rule numbers of the standard, the examples and the reasons. -->

Two layers, always on. **Layer 1** sets the words of each sentence. **Layer 2** sets the
shape of a reply to a person who has ADHD.

| Text | Layer 1 | Layer 2 |
|---|---|---|
| Chat reply, task, issue, PR description, commit message | yes | yes |
| README, reference doc, release note, tool description | yes | no |
| Error message, runbook, procedure, safety text | strict | no |
| Text that needs a voice: blog post, essay, video script, marketing copy | no | no |
| Code, identifiers, command syntax, log output | no | no |

## Layer 1: the words

**Modes.** STE-flavored is the default: all the rules below except the strict words,
with a free choice of common words. Strict applies to procedures, runbooks, safety text and error messages: also
the strict words, and the list in
[ste-recurring-errors.md](${CLAUDE_SKILL_DIR}/ste-recurring-errors.md).

Words:
- One name for one thing. Pick one verb for each action, and keep it.
- The short common word: start (for begin, commence, initiate), use (for utilize,
  leverage), help (for facilitate), make sure (for ensure), do (for perform, conduct),
  give (for provide), before (for prior to), after (for subsequent to), about (for
  regarding), get (for obtain, acquire), show (for demonstrate), also (for additionally,
  furthermore, moreover).
- One meaning for each word.
- Plain adjectives that carry a fact, never marketing adjectives (seamless, robust,
  powerful, cutting-edge).
- Strict words: but (for however), because (for since, for a cause), can (for may), must
  (for should and shall), use or with (for using), obey (for follow, for an instruction),
  push (for press, for a physical control).

Verbs:
- Active voice. Passive only in descriptive text, when the actor is unknown or
  irrelevant. A past participle as an adjective is fine ("the field is required").
- Simple tenses: infinitive, imperative, simple present, simple past, simple future.
  "We received the report", not the present perfect.
- A simple tense in place of an "-ing" main verb.
- One verb, with no stacked auxiliaries: "this improves X". Write "this can improve X"
  only with data that supports it.
- A verb for an action: "analyze the log".
- A one-word verb in place of a phrasal verb: start (for kick off, spin up), publish (for
  roll out), contact (for reach out).

Sentences:
- One instruction for each sentence, unless two actions happen at the same time. At most
  20 words for an instruction and 25 for other text.
- A condition before its command, with a comma: "If the test fails, read the log."
- Keep all the words: "Remove the bolts from the panel." Write each word in full, with no
  contraction.
- An article (a, an, the) or a demonstrative (this, these) before a noun, when it
  applies. A general statement takes none ("Solvents can cause damage to paint"). In a
  series, the article before the first noun is enough.
- Plain connectors between sentences: then, but, thus, as a result.
- A period where a semicolon would go.

Nouns and structure:
- A noun cluster has three words at most. Unpack a longer one, or hyphenate it.
- Define an abbreviation at its first use.
- One topic for each paragraph, six sentences at most.
- Steps go in a numbered list, one action for each item, in the imperative.
- A list item can be a short label ("Frontend receives session JWT"). Keep a label short:
  it needs no article.
- Safety text: WARNING (injury), CAUTION (damage), NOTE (information only). Put it just
  before the step that it protects, command or condition first.

## Layer 2: the shape

- **Lead with the next action.** The first line is a small action the reader can do now:
  a command, a path or a snippet. Prose comes after it.
- **Start with the answer, and stop when the answer is done.** The last line is the last
  fact or the next action.
- **Number a multi-step task**: one bounded action for each step.
- **Five action items at most** in a list of things the reader must act on. Split a longer
  list into "do now" and "later". Reference lists have no cap.
- **End with one action** when work stays open: one thing the reader can do in under two
  minutes.
- **State the step in each turn**: "Step 3 of 5 done: the schema is updated. Next: backfill the new
  column."
- **Show what works now**, in concrete terms: "Login works with magic links. Run
  `npm run dev`, then open `/login`."
- **An error** gets its place, cause and fix, with no emotion.
- **One issue at a time.** Offer a second issue as a separate question.
- **Hedges**: cut a hedge that carries no fact. Keep a qualifier that bounds a claim
  ("on macOS only", "n=6").

Break Layer 2 in four cases:
1. The reader asks for an explanation: explain in full, with headers. Keep the first and
   the last line rules.
2. A destructive action comes next: confirm before you act.
3. A fix failed and you have no new evidence: stop the edits, name the assumption that
   can be wrong, and ask one question or add one measurement.
4. The request is ambiguous: ask one short question.

## Check the text

A gate lints each chat reply after you send it. Send a chat reply with no lint run first.
When the gate blocks a reply, send the corrected reply alone, with every fact of the first
draft.

Before you write prose to a file (docs, commit messages, task trackers), or when the user
asks for a lint, read [lint.md](${CLAUDE_SKILL_DIR}/lint.md).

To rewrite or review existing text, read [review.md](${CLAUDE_SKILL_DIR}/review.md).
