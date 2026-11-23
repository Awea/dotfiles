# Board orchestrator: the board triage

This part of the board-orchestrator skill gives the triage rules T1 to T4. All the rules
of `SKILL.md` apply here.

A triage worker checks each open card of the board against the forge and git. It
proposes one change for each card that is done, obsolete or stale, and the user decides
in the worker. You apply only the approved changes. The worker has the name
`triage-<board>` and no card. It runs in the vault with read-only permissions.

Run the commands of this part in this form only:

```bash
bash ~/.claude/skills/board-orchestrator/dispatch.sh triage-check BOARD
bash ~/.claude/skills/board-orchestrator/dispatch.sh triage BOARD
bash ~/.claude/skills/board-orchestrator/dispatch.sh triage-apply BOARD REPORT
```

`triage-check` prints `triage: due N open cards, limit L`, or a `triage: not due` line.
Both exit 0: write nothing for `not due`. The limit is `triage-limit:` in the board
frontmatter, else 100. After a `due` line or a start, the next `due` line comes 14 days
later at the earliest.

`triage-apply` writes the board file itself, in one write: it is the one exception to the
MCP rule of "Tools" in `SKILL.md`. It finds each card by its exact text, and skips a card
that the user changed, a card that is on the board twice and a card with a live worker.

T1. **Offer.** After a `due` line of `triage-check` (rule 1a), ask with the questions of
    rule 4: "I ask: BOARD has N open cards (limit L). Start a triage?" A yes starts T2.
    Any other answer, or none: do nothing.
    Done: the user has the question.
T2. **Start.** On a yes to T1, or when the user asks for a triage of this board, run
    `bash ~/.claude/skills/board-orchestrator/dispatch.sh triage BOARD`. Line 1 of the
    output is the worker address, line 2 the report path. Tell the user "The triage
    worker started: <address>." On a nonzero exit, tell the user the stderr text. Log it
    (rule 7.10) with the title "Triage of BOARD" and the result "started".
    Done: the worker runs, or the user has the reason why it did not start.
T3. **Record a report.** A message `report triage-<board> <path>`:
    1. Run `bash ~/.claude/skills/board-orchestrator/dispatch.sh report <path>`. Edit no
       card for the report itself, and write no done line, also when `say:` gives one.
    2. When `## Vault changes` has items, ask this question:
       "I ask: apply the vault changes of the triage of BOARD?"
       Ask once for each report. For a new report of the same worker, ask again only
       when it has changes that the user did not see.
    3. On a yes, run
       `bash ~/.claude/skills/board-orchestrator/dispatch.sh triage-apply BOARD <path>`.
       Tell the user its output lines as they are: the `applied` line and each `skipped`
       line. `applied already`: tell the user that line, and skip step 4. Exit 1 with the
       line "the board changed during the run": run it once again. Another nonzero exit:
       tell the user the output and the stderr text.
    4. Apply the items after the `jsonl` block (for example the lessons for
       `Knowledge/Board triage procedure.md`) with the vault MCP tools, in the same yes.
    5. Log it (rule 7.10) with the title "Triage of BOARD", the `applied` line as the
       result, and the report path.
    Done: the user answered, and each approved change is on the board or in a `skipped`
    line that the user has.
T4. **Exit, close and resume.** There is no card to record for a triage worker.
    - Exit with no report: tell the user "The triage worker is gone with no report.",
      then run `dispatch.sh close <address>` ("no agent" is fine).
    - Exit with a report: run `dispatch.sh close <address>`. Write nothing.
    - Close request `close triage-<board>`, or a word of the user: run
      `dispatch.sh close <address>`, as rule 6 does. Write nothing.
    - A `workers` line (rule 1b) or a `resumable` line (rule 1c): when `report_exists` is
      true, run `bash ~/.claude/skills/board-orchestrator/dispatch.sh triage-apply BOARD <path> --check`.
      On `triage-apply: not applied`, do T3 for the report. On `applied already`, do
      nothing. Offer the resume of a closed triage worker with the other workers of
      rule 1c.
    Done: the worker is closed or adopted, or the user has the line.
