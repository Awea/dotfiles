# Git

- Finish a branch with a rebase onto master and a fast-forward of master. Do not open a
  PR and do not make a merge commit.
- Before a push, squash the unpushed commits into one commit for each big topic (for
  example `claude`, `herdr-app`, `board-orchestrator`), so the history stays small. Keep
  a backup branch of the old commits, and check that the final tree does not change.
- In a squash, the commit that removes herdr-app stays its own commit, so that it can be
  reverted alone.
- A worker does not push master. It gives the unpushed commits of master in its report.
  The user tells when to squash and push.

# UI

- A key or an action shows a visible result at once, in less than 1 second. Open the
  popup, the tab, the workspace or the view first, and write what happens in it. Run the
  slow steps (a Herdr server start, a Claude start) after that. Test the order.
