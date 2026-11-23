# Board triage

You triage one board of the vault. A triage finds the cards that are done, obsolete or
stale, with a proof for each, and gives the user one decision list. The user decides.
The orchestrator applies only the changes that the user approved.

Read only: the report is the one file you write. Read the board, the task notes, the
repos and the forge with `gh … view`, `gh … list`, the git reads and the files. Your
permissions refuse a vault or repo edit, a push, a forge write, a git write, `gh api`,
`board-ro` and `ssh`. Another write asks the user: do not make it. Live data and the
hosts of a project are not part of a triage.

## Classes

- **A Done**: the PR is merged or the commit is on the default branch, and nothing else
  of the card is open. Change: `done`.
- **B Obsolete**: closed with no merge, superseded, or a duplicate of another card.
  Change: `delete`. For a duplicate, also a `context` change on the card that stays, when
  it gets a link of the deleted card.
- **C Stale**: no real activity for 30 days or more, or a context line that is no longer
  true. Change: `context`, with the new state. The card stays in its column.
- **D Keep**: the state is current. Change: none, or a `title` or `context` fix of a
  wrong text.

A card with a worker address on its context line (8 hex digits, for example `01a1ef15`)
has a live worker: it is D, with no change.

A **proof** is the PR or issue state with its date, the commit on the default branch, or
the code on the default branch. Each A, B and C card has one.

## Steps

1. Read `Knowledge/Board triage procedure.md` in the vault: the board notes (forge,
   clones, default branch) and the lessons of the past triages. Done: you know the forge
   command and the clones of this board.
2. Read the cards file. It has one JSON line for each card of the open columns: `line`,
   `column`, `title`, `title_line`, `context_line`, `links`, `task`, `project` and
   `repo`. Its last line is the board summary. Done: you have the cards and their repos.
3. Fetch each repo once (`git -C <repo> fetch --prune`). Check each forge link of the
   cards once, and each PR or issue number in the card text ("PR 1219"). Done: one list
   of the PR and issue states, each with its date.
4. Split the cards into groups of about 30, by repo. Start one Explore subagent (model
   opus, effort high) for each group, all in one message. Give each the same brief: the
   classes, the repos, the states of step 3, the checks below, and one line for each
   card: `line<TAB>class<TAB>last activity<TAB>proof<TAB>change`. Tell them to grep the
   command output: an Explore subagent cannot write a file. Done: each card has one class.
5. Check the proof of each A card again yourself, and of some B cards. A merged PR does
   not prove that the card is done: when the card asks for a behavior, read the code on
   the default branch. A subagent can give a wrong SHA. Done: you checked the proof of
   each A card.
6. Show the decision list in the conversation: a table for A, B and C (line, card, proof,
   change), and the D count. Ask the user at most 3 questions: approve A, approve B, and
   C with a default ("keep all with the new context line"). Done: the user decided each A,
   B and C change.
7. Write the report (below). Done: its `jsonl` block has each approved change, and no
   other change.

## Checks for each card

1. Read the task note. Collect the PR and issue numbers, the commit SHAs, and the branch
   and worktree names.
2. Commit: `git -C <repo> merge-base --is-ancestor <sha> origin/<default>`. A rebase, a
   squash or a cherry-pick gives a new SHA: also search the subject with
   `git -C <repo> log origin/<default> -i --grep=<word>`, and grep the code. Branch:
   `git -C <repo> ls-remote --heads origin <branch>`, then `git -C <repo> worktree list`.
3. Search the default branch for work with no link on the card: `git log --grep` with the
   words of the title, and the code symbol. Some repos get commits with no PR.
4. Last real activity: the newest dated line of the task note, the commit date of the
   branch, and the lines of the card in the orchestrator dev logs
   (`Dev Logs/<date> - <board> (board orchestrator).md`). The `updated:` field of a note
   and the `updatedAt` of a PR are not activity: a copy from the board or a force push
   of the base branch changes them.

## Report

Start with one line: `RESULT: DONE`, or `RESULT: WAITS FOR USER` while a decision is
open. Then:

- `## Result`: at most 10 lines. The count of each class, and the decisions of the user.
- `## A. Done`, `## B. Obsolete`, `## C. Stale`: one table each (line, card, proof).
- `## D. Keep`: the count, and the text fixes.
- `## Vault changes`: first a fenced block with the info string `jsonl`, its fence at the
  start of the line. It has one line
  for each approved change, for example:

```jsonl
{"op":"done","title_line":"- [ ] 🟢 **[web] Fix the login**","context_line":"\tPR open. [[Projects/web]]","new":"Merged: PR 12, 2026-11-20. [[Projects/web]]"}
```

  - `op`: `done`, `delete`, `context` or `title`.
  - `title_line` and `context_line`: copy them from the cards file with `jq`. The apply
    finds the card by this exact text.
  - `new`: for `context`, the new context text with no tab, at most 180 characters, with
    the `[[Tasks/...]]` and `[[Projects/...]]` links of the old text. For `title`, the
    full new title line. For `done`, optional: the new context text, with the proof link.

  After the block, write the lessons of this triage for
  `Knowledge/Board triage procedure.md`: the note path and the exact old and new text.
  The orchestrator asks the user before it applies them.
