// alt-shift-b: pick a board with one key, then show or start its orchestrator.
// board.sh does the work. The popup stays until board.sh is done (well under 1 s), so an
// error shows here, never as a toast.
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

export default class BoardOpen extends View {
  init(_props, cx) {
    this.boards = null;
    this.message = "";
    this.busy = false;
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(100, () => this.handle.focus());
    cx.spawn(async (cx) => {
      const r = await runBoard(["boards"], 5000);
      if (r.code === 0) this.boards = JSON.parse(r.stdout);
      else this.message = firstLine(r.stderr) || "board.sh boards failed.";
      if (this.boards && this.boards.length === 0) this.message = "No board in the vault.";
      cx.notify();
    });
  }

  pick(board, cx) {
    if (this.busy) return;
    this.busy = true;
    this.message = `Opening ${board}…`;
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await runBoard(["open", board], 15000);
      this.busy = false;
      if (r.code === 0) return closeOverlay(props().overlay);
      this.message = firstLine(r.stderr) || `board.sh open ${board} failed.`;
      cx.notify();
    });
  }

  key(e, cx) {
    if (e.key === "escape") closeOverlay(props().overlay);
    else {
      const b = (this.boards ?? []).find((x) => x.key === e.key);
      if (!b) return;
      this.pick(b.board, cx);
    }
    cx.stop_propagation();
  }

  render() {
    return popup(this, "Open a board orchestrator", this.boards, (b, cx) => this.pick(b, cx));
  }
}

function firstLine(text) {
  return (text ?? "").split("\n").find((l) => l.trim()) ?? "";
}

// popup(view, title, boards, pick): the board list with one key for each board.
function popup(view, title, boards, pick) {
  const t = theme();
  return v_flex().id("board-popup").track_focus(view.handle).on_key_down((e, cx) => view.key(e, cx))
    .w_full().min_h(0).p(18).gap(8).bg(t.popover).text_color(t.foreground).text_size(13)
    .child(h_flex().items_center()
      .child(div().flex_1().text_size(15).font_semibold().child(title))
      .child(div().text_size(11).text_color(t.dim).child("Esc")))
    .children((boards ?? []).map((b) => h_flex().id(`board-${b.key}`).gap(10).px(8).py(4).rounded(6)
      .cursor_pointer().hover((s) => s.bg(t.hover)).on_click((_e, cx) => pick(b.board, cx))
      .child(div().text_color(t.accent).font_semibold().child(`[${b.key}]`))
      .child(div().child(b.board))))
    .when(Boolean(view.message), (el) => el.child(div().pt(6).text_size(12).text_color(t.muted).child(view.message)));
}
