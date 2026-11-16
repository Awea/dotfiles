# Board orchestrator: shorten the long cards

This part of the board-orchestrator skill gives rule 9. `SKILL.md` gives what you write,
the tools, the output of `card` and the other rules. All its rules apply here.

Run the command of this part in this form only, with `bash`:

```bash
bash ~/.claude/skills/board-orchestrator/dispatch.sh note-add NOTE BOARD LINE TITLE
```

9. **Shorten long cards.** A card is a short pointer. The details are in its task note.
   The scan marks a context line of more than 200 characters, its other links included,
   with no count for the tab and for the `[[Tasks/...]]` and `[[Projects/...]]` links.
   Write at most 180 characters, counted the same way: the margin stops a second copy of
   the same card at the next scan. The line holds the state in a few words, the
   `owner:` and `waits for` text of the old line (rule 2 skips cards with them), and
   these links: the newest PR or commit, the worker address or session (rule 7.8),
   `[[Tasks/...]]` and `[[Projects/...]]`. Write `owner:` and `waits for` in lower case:
   the scan finds only that form, also at the start of a sentence. Never drop the
   `[[Tasks/...]]` or the `[[Projects/...]]` link: the scan gets the task note and the
   repo of the card from them. When the line does not fit, cut the state text first, then
   the worker address or the session. The user and other Claude sessions also write cards, so a
   long card can come back. Do this pass for each card of `cards` with `context_long`
   true, one card at a time. Do it after rule 4, and after a new `cards` scan. When you give the pass to a subagent, give it
   the full text of this rule 9 unchanged: on 2026-11-05 a subagent prompt with a changed
   rule dropped the `[[Projects/...]]` link of 9 open cards.
   1. Run `board-scan.sh card BOARD '<title>'` and find the card line (the rule of the
      `card` command). Its `context_line` is the full text. When `context_long` is now
      false, the user changed the card: leave it.
   2. When `task_exists` is false, make the task note first with
      `mcp__plugin_obsidian-second-brain_vault__obsidian_save_note`. The path is `task`
      of the `card` line of step 1, or `Tasks/<title with no [project] part>.md` when `task` is null.
      Give `type` `task`, `tags` `["task"]`, the title with no `[project]` part, a
      `summary` of one sentence, and as `content` only the title heading. The tool writes
      the frontmatter from `type` and `tags`: put no frontmatter in `content`, or the note
      gets a second block in its body. Do not put the card text in it. Then run
      `obsidian_update_note` on the note with `set_fields`
      `{"status": "open", "priority": "<the emoji of the card>", "project": "[[Projects/...]]"}`
      (the `[[Projects/...]]` link of the card). Step 4 adds the `[[Tasks/...]]` link of
      the new note to the card.
   3. Run `bash ~/.claude/skills/board-orchestrator/dispatch.sh note-add '<task>' BOARD <line> '<title>'`
      (`line` and `title` of that `card` output). It checks that the card is still at
      that line. It copies the full context text to the task note,
      under `## Notes`, then `### YYYY-MM-DD, from the board`. Do not write that text
      yourself, and do not read the note. On exit 1, run step 1 again and retry once. On
      a second failure, or on exit 2, tell the user the stderr text and leave the card.
   4. Write the new context line from the full text: at most 180 characters, with the
      `owner:` and `waits for` text and the links of the list above. Keep the newest state
      and the newest PR or commit link only: the older links are in the task note. Replace
      the whole old `context_line` (all its lines) with one tab-indented line, with
      `obsidian_replace_text`. Use the full `context_line` of step 1 as `old_text`. Change
      nothing else of the card.
   5. When the replace fails, run step 1 again and retry once. When it fails again, tell
      the user the card title. The text is already in the task note: run no second
      `note-add` for that card.
   When the user writes during the pass, finish the card that you started, answer the
   user, then continue. At the end, tell the user "I shortened N cards." in one line.
   Write no line when N is 0. Do not log the pass (rule 7.10).
