// ctrl+b a: ask a prompt, an effort and the focus, then start claude in a new tab. In a
// linked git worktree, claude starts in the main checkout (agent-tabs new-agent-tab.sh).
import { View } from "gpui-kit";
import { InputState } from "gpui-base";
import { focused, run } from "herdr";
import { runScript, close, firstLine, effortKey, focusKey, claudeArgv, frame, line, input, QUESTIONS } from "./ask.js";

export default class NewAgentTab extends View {
  init(_props, cx) {
    this.from = focused();
    this.step = "prompt";
    this.message = "";
    this.folder = this.from?.cwd ?? null;
    this.input = InputState.new({ placeholder: "Prompt for the new claude (Enter for a clean tab)" });
    this.input.on("submit", (_e, cx) => { this.prompt = this.input.value().trim(); this.next("effort", cx); });
    this.input.focus();
    cx.timer.after(100, () => { if (this.step === "prompt") this.input.focus(); });
    this.handle = cx.focus_handle();
    // The folder before the questions end: a closed popup ends its tasks.
    if (this.folder) cx.spawn(async (cx) => {
      const r = await runScript(["main-folder", this.folder], 2000);
      if (r.code === 0 && r.stdout.trim()) this.folder = r.stdout.trim();
      else this.message = firstLine(r.stderr);
      cx.notify();
    });
  }

  next(step, cx) { this.step = step; this.handle.focus(); cx.notify(); }

  start(foreground) {
    const tab = { argv: claudeArgv(this.effort), ...(this.folder ? { folder: this.folder } : {}) };
    if (this.prompt) tab.task = this.prompt;
    close();
    run("tab.new", tab);
    if (!foreground && this.from?.tab) run("tab.select", { id: this.from.tab });
  }

  key(e, cx) {
    if (e.key === "escape") { close(); return cx.stop_propagation(); }
    if (this.step === "effort") {
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
  }

  render() {
    const body = this.step === "prompt" ? [input(this.input)]
      : [line(`Prompt: ${this.prompt || "(none)"}`), line(QUESTIONS[this.step])];
    return frame(this, "New claude tab", body);
  }
}
