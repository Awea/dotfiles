// alt-shift-x: stop a board orchestrator. With one running, stop it at once; with more,
// pick it with one key. board.sh does the work; an error shows here, never as a toast.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, home, props, closeOverlay, theme } from "herdr";

const SCRIPT = () => `${home()}/.claude/skills/board-orchestrator/board.sh`;

// runBoard(args, ms): run board.sh. A failed start or a time-out gives code -1 and the
// reason in stderr, so the popup always shows a result.
async function runBoard(args, ms) {
  try {
    return await exec("bash", [SCRIPT(), ...args], { timeout: ms });
  } catch (e) {
    return { code: -1, stdout: "", stderr: `board.sh ${args[0]}: ${e?.message ?? e}` };
  }
}

export default class BoardStop extends View {
  init(_props, cx) {
    this.boards = null;
    this.message = "";
    this.busy = false;
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(100, () => this.handle.focus());
    cx.spawn(async (cx) => {
      const r = await runBoard(["running"], 5000);
      if (r.code !== 0) {
        this.message = firstLine(r.stderr) || "board.sh running failed.";
        return cx.notify();
      }
      const names = JSON.parse(r.stdout);
      if (names.length === 0) this.message = "No board orchestrator runs.";
      else if (names.length === 1) return this.pick(names[0], cx);
      else this.boards = names.map((n, i) => ({ key: String(i + 1), board: n }));
      cx.notify();
    });
  }

  pick(board, cx) {
    if (this.busy) return;
    this.busy = true;
    this.message = `Stopping ${board}…`;
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await runBoard(["stop", board], 15000);
      this.busy = false;
      if (r.code === 0) return closeOverlay(props().overlay);
      this.message = firstLine(r.stderr) || `board.sh stop ${board} failed.`;
      cx.notify();
    });
  }

  key(e, cx) {
    // With nothing to pick, any key closes the popup.
    if (e.key === "escape" || !this.boards) closeOverlay(props().overlay);
    else {
      const b = this.boards.find((x) => x.key === e.key);
      if (!b) return;
      this.pick(b.board, cx);
    }
    cx.stop_propagation();
  }

  render() {
    const t = theme();
    return v_flex().id("board-popup").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .w_full().min_h(0).p(18).gap(8).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().child("Stop a board orchestrator"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .children((this.boards ?? []).map((b) => h_flex().id(`board-${b.key}`).gap(10).px(8).py(4).rounded(6)
        .cursor_pointer().hover((s) => s.bg(t.hover)).on_click((_e, cx) => this.pick(b.board, cx))
        .child(div().text_color(t.accent).font_semibold().child(`[${b.key}]`))
        .child(div().child(b.board))))
      .when(Boolean(this.message), (el) => el.child(div().pt(6).text_size(12).text_color(t.muted).child(this.message)));
  }
}

function firstLine(text) {
  return (text ?? "").split("\n").find((l) => l.trim()) ?? "";
}
