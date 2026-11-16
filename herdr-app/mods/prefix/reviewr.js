// The choices of ctrl+b d (reviewr), without herdr calls, so that node can test them
// (herdr-app/test/prefix-reviewr.bats). panes and terminals: panes() and terminals().

// reviewrDir(t): the folder of terminal t when it runs agent-tabs.sh reviewr, else null.
export function reviewrDir(t) {
  const a = t?.argv ?? [];
  return /(^|\/)agent-tabs\.sh$/.test(a[1] ?? "") && a[2] === "reviewr" ? a[3] ?? null : null;
}

// openReviewr({focus, panes, terminals, root}): the pane to show for ctrl+b d, else null.
// That is the focused pane when it is a reviewr, else a reviewr of root in the same tab.
export function openReviewr({ focus, panes, terminals, root }) {
  const dir = (p) => reviewrDir(terminals.find((t) => t.address === p.terminal));
  const me = panes.find((p) => p.pane === focus.pane);
  if (me && dir(me) !== null) return me.pane;
  return panes.find((p) => p.tab === focus.tab && p.pane !== focus.pane && p.terminal &&
    dir(p) === root)?.pane ?? null;
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
