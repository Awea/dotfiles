// ctrl+b shift+n: pick a frequent folder, then open a space there (workspaces
// new-workspace.sh). Enter: a shell. Tab: ask a prompt, an effort and the focus, then
// start claude in the space.
import { View, div } from "gpui-kit";
import { InputState, h_flex } from "gpui-base";
import { focused, home, nextCommand, run, theme } from "herdr";
import { runScript, close, firstLine, effortKey, focusKey, claudeArgv, frame, line, input, QUESTIONS } from "./ask.js";

const pretty = (dir) => (dir === home() || dir.startsWith(home() + "/")) ? "~" + dir.slice(home().length) : dir;

export default class NewSpace extends View {
  init(_props, cx) {
    this.from = focused();
    this.step = "pick";
    this.message = "";
    this.folders = [];
    this.at = 0;
    this.filter = InputState.new({ placeholder: "Filter the folders (Enter: shell, Tab: claude)" });
    this.filter.on("change", (_e, cx) => { this.at = 0; cx.notify(); });
    this.filter.on("submit", () => this.open(false));
    this.filter.focus();
    cx.timer.after(100, () => { if (this.step === "pick") this.filter.focus(); });
    this.prompt = InputState.new({ placeholder: "Prompt for the new claude (Enter for a clean claude)" });
    this.prompt.on("submit", (_e, cx) => { this.promptText = this.prompt.value().trim(); this.next("effort", cx); });
    this.handle = cx.focus_handle();
    // Tab is an app action (focus the next field): it never reaches on_key_down or a
    // keys.json mod section. A binding of our own under the pick step key context
    // comes first (win98 menu.js does the same for Escape). The first entry beats
    // the Tab binding of the filter field, the second the Tab binding of the window.
    try {
      cx.bind_keys([
        { keystroke: "tab", action: "new_space_claude", context: "NewSpacePick > Input" },
        { keystroke: "tab", action: "new_space_claude", context: "NewSpacePick" },
      ]);
    } catch {}
    // The filter field keeps up and down for itself. keys.json section mod:new-space
    // sends them here as commands.
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (this.step !== "pick") continue;
        const n = this.shown().length;
        if (c === "down" && n) this.at = (this.at + 1) % n;
        else if (c === "up" && n) this.at = (this.at + n - 1) % n;
        cx.notify();
      }
    });
    cx.spawn(async (cx) => {
      const r = await runScript(["folders"], 3000);
      if (r.code === 0) { try { this.folders = JSON.parse(r.stdout); } catch {} }
      else this.message = firstLine(r.stderr);
      cx.notify();
    });
  }

  shown() {
    const q = this.filter.value().toLowerCase();
    return this.folders.filter((d) => pretty(d).toLowerCase().includes(q));
  }

  next(step, cx) { this.step = step; this.handle.focus(); cx.notify(); }

  open(withClaude, cx) {
    const dir = this.shown()[this.at];
    if (!dir) return;
    this.dir = dir;
    if (!withClaude) { close(); run("space.new", { folder: dir }); return; }
    this.step = "prompt";
    this.prompt.focus();
    cx?.notify();
  }

  start(foreground) {
    const space = { folder: this.dir, argv: claudeArgv(this.effort) };
    if (this.promptText) space.task = this.promptText;
    close();
    run("space.new", space);
    if (!foreground && this.from?.space) run("space.select", { id: this.from.space });
  }

  key(e, cx) {
    if (e.key === "escape") { close(); return cx.stop_propagation(); }
    if (this.step === "pick") {
      const n = this.shown().length;
      if (e.key === "down" && n) this.at = (this.at + 1) % n;
      else if (e.key === "up" && n) this.at = (this.at + n - 1) % n;
      else return;
    } else if (this.step === "effort") {
      const eff = effortKey(e);
      if (eff === undefined) return;
      this.effort = eff;
      this.next("focus", cx);
    } else if (this.step === "focus") {
      const f = focusKey(e);
      if (f === undefined) return;
      this.start(f);
    } else return;
    cx.stop_propagation();
    cx.notify();
  }

  render() {
    const t = theme();
    let body;
    if (this.step === "pick") {
      body = [input(this.filter), ...this.shown().slice(0, 8).map((d, i) =>
        h_flex().id(`dir-${i}`).px(8).py(3).rounded(6).when(i === this.at, (el) => el.bg(t.selected))
          .child(div().child(pretty(d))))];
    } else if (this.step === "prompt") {
      body = [line(`Folder: ${pretty(this.dir)}`), input(this.prompt)];
    } else {
      body = [line(`Folder: ${pretty(this.dir)}`), line(QUESTIONS[this.step])];
    }
    const popup = frame(this, "New space", body);
    if (this.step !== "pick") return popup;
    return popup.key_context("NewSpacePick").on_action("new_space_claude", (_e, cx) => this.open(true, cx));
  }
}
