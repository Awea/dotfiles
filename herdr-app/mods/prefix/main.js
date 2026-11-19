// ctrl+b: the prefix keys of Herdr 0.9.5. The popup reads the next key and runs its
// action (the table below), then closes. Esc, a second ctrl+b or an unknown key close it.
// A second ctrl+b sends nothing to the program (David, 2026-11-13).
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, focused, home, openOverlay, closeOverlay, panes, props, run, terminals, theme } from "herdr";
import { newPane, openReviewr, pickRoot, reviewTarget, zoomSteps } from "./reviewr.js";

const SCRIPT = () => `${home()}/.config/herdr-app/bin/agent-tabs.sh`;
const close = () => { const id = props()?.overlay; if (id) closeOverlay(id); };
const mod = (name) => () => run("mod.open", { name });
const split = (direction) => () => run("pane.split", { direction });
const go = (direction) => () => run("pane.go", { direction });

// KEYS: key name → [help text, action(cx)]. An action that returns a promise keeps the popup
// open until it ends (a closed popup ends its tasks).
const KEYS = {
  "a": ["new claude tab", mod("new-agent-tab")],
  "shift-a": ["handoff", mod("handoff")],
  "c": ["shell tab", shellTab],
  "%": ["split right", split("right")],
  "v": ["split right", split("right")],
  "\"": ["split down", split("down")],
  "-": ["split down", split("down")],
  "shift-b": ["board", mod("board-open")],
  "shift-x": ["board stop", mod("board-stop")],
  "shift-n": ["new space", mod("new-space")],
  "d": ["reviewr", reviewr],
  "x": ["close pane", () => run("pane.close", {})],
  "shift-d": ["close space", () => run("space.close", {})],
  "z": ["zoom", () => run("pane.zoom", {})],
  "h": ["pane left", go("left")],
  "j": ["pane down", go("down")],
  "k": ["pane up", go("up")],
  "l": ["pane right", go("right")],
  "tab": ["pane right", go("right")],
  "shift-tab": ["pane left", go("left")],
  "n": ["next tab", () => run("tab.next", {})],
  "p": ["previous tab", () => run("tab.prev", {})],
  "b": ["sidebar", () => run("layout.toggle", { id: "sidebar" })],
  "g": ["go to", mod("picker")],
  "w": ["go to", mod("picker")],
  "?": ["help", () => run("app.help", {})],
  "s": ["settings", () => run("app.settings", {})],
  "shift-t": ["rename tab", () => run("tab.rename", {})],
  "shift-w": ["rename space", () => run("space.rename", {})],
  "shift-g": ["new worktree", () => openOverlay({ mod: "worktree", props: { space: focused()?.space, action: "new" }, kind: "dialog" })],
};
for (let i = 1; i <= 9; i++) KEYS[String(i)] = [`tab ${i}`, () => run("tab.select", { index: i })];

// The help line: one entry for each action.
const HELP = "a claude · A handoff · c shell · % \" split · B board · X stop · N space · d reviewr · x close · z zoom · hjkl panes · n p 1-9 tabs · b sidebar · g go to · ? help";

// reviewr(cx): herdr-reviewr on the git root of the focused folder, zoomed. The labels
// reviewr.dir and reviewr.base of the focused terminal replace that folder, and start the
// branch scope on that base (reviewTarget). It shows the reviewr of that root and base in
// the tab, else opens one in a split on the right. Its herdr calls go to herdr-shim
// (agent-tabs.sh reviewr).
async function reviewr(cx) {
  const f = focused();
  if (!f?.pane) return;
  const cwd = f.cwd ?? home();
  const labels = terminals().find((t) => t.address === f.terminal)?.labels ?? null;
  const target = reviewTarget(labels, cwd);
  const { root, base } = await pickRoot(target, cwd, async (d) => {
    try {
      const r = await exec("git", ["-C", d, "rev-parse", "--show-toplevel"],
        { timeout: d === cwd ? 2000 : 1000 });
      return r.code === 0 && r.stdout.trim() ? r.stdout.trim() : null;
    } catch {
      return null;
    }
  });
  let pane = openReviewr({ focus: f, panes: panes(), terminals: terminals(), root, base });
  if (!pane) {
    const before = new Set(panes().map((p) => p.pane));
    const argv = ["bash", SCRIPT(), "reviewr", root, ...(base ? [base] : [])];
    run("pane.split", { direction: "right", pane: f.pane, argv });
    // The new pane shows in panes() at once, or after a few frames: wait 1 s at most.
    for (let i = 0; !(pane = newPane(before, panes(), f.tab)) && i < 20; i++) {
      await new Promise((done) => cx.timer.after(50, done));
    }
    if (!pane) return;
  }
  run("pane.focus", { pane });
  for (const p of zoomSteps(panes(), f.tab, pane)) run("pane.zoom", { pane: p });
}

// shellTab: a shell tab in the main checkout of the focused folder.
async function shellTab() {
  const cwd = focused()?.cwd;
  let folder = cwd;
  if (cwd) {
    try {
      const r = await exec("bash", [SCRIPT(), "main-folder", cwd], { timeout: 2000 });
      if (r.code === 0 && r.stdout.trim()) folder = r.stdout.trim();
    } catch {}
  }
  run("tab.new", folder ? { folder } : {});
}

const MODIFIERS = ["shift", "control", "ctrl", "alt", "meta", "cmd", "super", "platform", "function"];

// names(e): the names a key press can have in KEYS, the most exact first. With ctrl, alt
// or cmd held, only the full keystroke counts: ctrl+b ctrl+x must not close the pane.
function names(e) {
  const out = [];
  if (e.keystroke) out.push(e.keystroke);
  const m = e.modifiers ?? {};
  if (m.control || m.alt || m.platform || m.function) return out;
  if (e.key) {
    out.push(e.key);
    if (e.modifiers?.shift) out.push(`shift-${e.key.toLowerCase()}`);
  }
  if (e.key_char) out.push(e.key_char);
  return out;
}

export default class Prefix extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(100, () => this.handle.focus());
  }

  key(e, cx) {
    cx.stop_propagation();
    if (MODIFIERS.includes((e.key ?? "").toLowerCase())) return;
    const all = names(e);
    const hit = all.map((n) => KEYS[n]).find(Boolean);
    if (!hit || e.key === "escape" || all.includes("ctrl-b")) return close();
    // An action gets the cx of its task: a mod must not keep the cx of the key event.
    cx.spawn(async (cx) => { try { await hit[1](cx); } finally { close(); } });
  }

  render() {
    const t = theme();
    return v_flex().id("prefix").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .w_full().min_h(0).p(16).gap(8).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().child("ctrl+b"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(div().text_color(t.muted).child(HELP));
  }
}
