// ctrl+b shift+a: run /handoff in the focused claude, then continue in a new tab
// (agent-tabs handoff.sh). agent-tabs.sh handoff-start does the long part, detached.
import { View } from "gpui-kit";
import { InputState } from "gpui-base";
import { focused, hc } from "herdr";
import { runScript, close, firstLine, effortKey, focusKey, frame, line, input, QUESTIONS } from "./ask.js";

export default class Handoff extends View {
  init(_props, cx) {
    this.from = focused();
    this.step = "check";
    this.message = "";
    this.input = InputState.new({ placeholder: "Focus for the next session (Enter to skip)" });
    this.input.on("submit", (_e, cx) => { this.focusText = this.input.value().trim(); this.next("effort", cx); });
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.spawn(async (cx) => {
      let ok = false;
      if (this.from?.terminal) {
        try {
          const r = await hc(["get", this.from.terminal, "--json"]);
          const t = r.code === 0 ? JSON.parse(r.stdout) : {};
          ok = t.state === "live" && t.status?.app === "claude-code" && ["idle", "done"].includes(t.status?.state);
        } catch {}
      }
      if (ok) { this.step = "focus-text"; this.input.focus(); }
      else { this.step = "refused"; this.message = "Focus an idle claude agent, then try again."; }
      cx.notify();
    });
  }

  next(step, cx) { this.step = step; this.handle.focus(); cx.notify(); }

  key(e, cx) {
    if (e.key === "escape" || this.step === "refused") { close(); return cx.stop_propagation(); }
    if (this.step === "effort") {
      const eff = effortKey(e);
      if (eff === undefined) return;
      this.effort = eff;
      this.next("tab-focus", cx);
    } else if (this.step === "tab-focus") {
      const f = focusKey(e);
      if (f === undefined) return;
      this.step = "start";
      this.message = "Starting the handoff…";
      cx.notify();
      const f2 = this.from;
      cx.spawn(async (cx) => {
        const r = await runScript(["handoff-start", f2.terminal, f2.space, f2.tab, this.focusText ?? "",
          this.effort ?? "", f ? "focus" : "background"], 5000);
        if (r.code === 0) return close();
        this.message = firstLine(r.stderr) || "agent-tabs.sh handoff-start failed.";
        this.step = "refused";
        cx.notify();
      });
    } else return;
    cx.stop_propagation();
  }

  render() {
    const body = this.step === "focus-text" ? [input(this.input)]
      : ["effort", "tab-focus"].includes(this.step)
        ? [line(`Focus: ${this.focusText || "(none)"}`), line(QUESTIONS[this.step === "effort" ? "effort" : "focus"])]
        : [];
    return frame(this, "Handoff to a new claude tab", body);
  }
}
