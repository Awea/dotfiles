#!/usr/bin/env bats
# The choices of ctrl+b d (herdr-app/mods/prefix/reviewr.js): reuse an open reviewr, zoom.

setup() {
  command -v node >/dev/null || skip "node is not installed"
  # node 22.0 reads ES modules only from .mjs files.
  cp "$BATS_TEST_DIRNAME/../mods/prefix/reviewr.js" "$BATS_TEST_TMPDIR/reviewr.mjs"
}

# check JS: run JS with the module as m, and the panes and terminals of a tab:
# p1 claude in /r, p2 a reviewr of /r, p3 a reviewr of /other, p4 in another tab.
check() {
  run node --input-type=module -e "
    import assert from 'node:assert/strict';
    const m = await import('$BATS_TEST_TMPDIR/reviewr.mjs');
    const rv = (dir) => ['bash', '/home/u/.config/herdr-app/bin/agent-tabs.sh', 'reviewr', dir];
    const terminals = [
      { address: 't1', argv: ['claude'] },
      { address: 't2', argv: rv('/r') },
      { address: 't3', argv: rv('/other') },
      { address: 't4', argv: rv('/r') },
    ];
    const panes = [
      { pane: 'p1', tab: 'a', terminal: 't1', zoomed: false },
      { pane: 'p2', tab: 'a', terminal: 't2', zoomed: false },
      { pane: 'p3', tab: 'a', terminal: 't3', zoomed: false },
      { pane: 'p4', tab: 'b', terminal: 't4', zoomed: false },
    ];
    $1"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "the reviewr of the same root in the tab is reused" {
  check "assert.equal(m.openReviewr({ focus: { pane: 'p1', tab: 'a' }, panes, terminals, root: '/r' }), 'p2');"
}

@test "a reviewr of another root or in another tab is not reused" {
  check "assert.equal(m.openReviewr({ focus: { pane: 'p1', tab: 'a' }, panes, terminals, root: '/x' }), null);
    assert.equal(m.openReviewr({ focus: { pane: 'p9', tab: 'b' }, panes: panes.filter((p) => p.pane !== 'p4'), terminals, root: '/r' }), null);"
}

@test "a focused reviewr is the one to zoom" {
  check "assert.equal(m.openReviewr({ focus: { pane: 'p3', tab: 'a' }, panes, terminals, root: '/r' }), 'p3');"
}

@test "zoom steps unzoom another pane of the tab first, and skip a zoomed target" {
  check "assert.deepEqual(m.zoomSteps(panes, 'a', 'p2'), ['p2']);
    const z = panes.map((p) => ({ ...p, zoomed: p.pane === 'p1' || p.pane === 'p4' }));
    assert.deepEqual(m.zoomSteps(z, 'a', 'p2'), ['p1', 'p2']);
    assert.deepEqual(m.zoomSteps(z, 'a', 'p1'), []);"
}

@test "the new pane is the one that was not in the tab before the split" {
  check "assert.equal(m.newPane(new Set(['p1', 'p2', 'p3', 'p4']), [...panes, { pane: 'p5', tab: 'a' }], 'a'), 'p5');
    assert.equal(m.newPane(new Set(['p1', 'p2', 'p3', 'p4']), panes, 'a'), null);"
}
