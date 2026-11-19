// The choices of ctrl+b d (reviewr), without herdr calls, so that node can test them
// (herdr-app/test/prefix-reviewr.bats). panes and terminals: panes() and terminals().

// reviewrDir(t): the folder of terminal t when it runs agent-tabs.sh reviewr, else null.
export function reviewrDir(t) {
  const a = t?.argv ?? [];
  return /(^|\/)agent-tabs\.sh$/.test(a[1] ?? "") && a[2] === "reviewr" ? a[3] ?? null : null;
}

// reviewTarget(labels, cwd): the folder and the base to review. An agent sets the labels
// reviewr.dir and reviewr.base on its hc terminal when its branch is in another worktree
// (claude/CLAUDE.md). With no reviewr.dir: cwd and no base.
export function reviewTarget(labels, cwd) {
  const dir = labels?.["reviewr.dir"];
  return dir ? { dir, base: labels["reviewr.base"] || null } : { dir: cwd, base: null };
}

// pickRoot({dir, base}, cwd, rootOf): the git root to review and its base. rootOf(d) gives
// the git root of folder d, else null. A labeled worktree that is gone gives the root of
// cwd with no base, and no root at all gives cwd.
export async function pickRoot({ dir, base }, cwd, rootOf) {
  if (dir !== cwd) {
    const root = await rootOf(dir);
    if (root) return { root, base };
  }
  return { root: (await rootOf(cwd)) ?? cwd, base: null };
}

// openReviewr({focus, panes, terminals, root, base}): the pane to show for ctrl+b d, else
// null. That is the focused pane when it is a reviewr, else a reviewr of root in the same
// tab with the same base (agent-tabs.sh reviewr DIR [BASE]).
export function openReviewr({ focus, panes, terminals, root, base = null }) {
  const term = (p) => terminals.find((t) => t.address === p.terminal);
  const dir = (p) => reviewrDir(term(p));
  const me = panes.find((p) => p.pane === focus.pane);
  if (me && dir(me) !== null) return me.pane;
  return panes.find((p) => p.tab === focus.tab && p.pane !== focus.pane && p.terminal &&
    dir(p) === root && (term(p).argv[4] ?? null) === base)?.pane ?? null;
}

// zoomSteps(panes, tab, pane): the panes to give pane.zoom, in order, so that tab shows
// only pane. pane.zoom toggles, so first unzoom another zoomed pane of the tab.
export function zoomSteps(panes, tab, pane) {
  const inTab = panes.filter((p) => p.tab === tab);
  if (inTab.some((p) => p.pane === pane && p.zoomed)) return [];
  return [...inTab.filter((p) => p.zoomed).map((p) => p.pane), pane];
}

// newPane(before, panes, tab): the pane of tab that is not in the set before, else null.
export function newPane(before, panes, tab) {
  return panes.find((p) => p.tab === tab && !before.has(p.pane))?.pane ?? null;
}
