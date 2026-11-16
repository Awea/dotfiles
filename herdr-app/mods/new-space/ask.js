// The questions of the agent-tabs popups (agent-tabs/lib.sh read_effort and read_focus),
// shared by copy: a mod imports only from its own folder.
import { div } from "gpui-kit";
import { v_flex, h_flex, Input } from "gpui-base";
import { exec, home, closeOverlay, props, theme } from "herdr";

export const SCRIPT = () => `${home()}/.config/herdr-app/bin/agent-tabs.sh`;

// runScript(args, ms): run agent-tabs.sh. A failed start or a time-out gives code -1
// and the reason in stderr, so the popup always shows a result.
export async function runScript(args, ms) {
  try {
    return await exec("bash", [SCRIPT(), ...args], { timeout: ms });
  } catch (e) {
    return { code: -1, stdout: "", stderr: `agent-tabs.sh ${args[0]}: ${e?.message ?? e}` };
  }
}

// close(): close this popup. herdr-app check gives no overlay id.
export const close = () => { const id = props()?.overlay; if (id) closeOverlay(id); };

export const firstLine = (text) => (text ?? "").split("\n").find((l) => l.trim()) ?? "";

export const EFFORTS = { l: "low", m: "medium", h: "high", x: "xhigh", M: "max" };

// effortKey(e): the effort of a key press, "" for Enter, undefined for another key.
export function effortKey(e) {
  if (e.key === "enter") return "";
  const k = e.modifiers?.shift && e.key.length === 1 ? e.key.toUpperCase() : e.key;
  return EFFORTS[k];
}

// focusKey(e): true for y, false for n or Enter, undefined for another key.
export function focusKey(e) {
  if (e.key === "y") return true;
  if (e.key === "n" || e.key === "enter") return false;
  return undefined;
}

// claudeArgv(effort, name): the argv of a new claude.
export const claudeArgv = (effort, name) =>
  ["claude", ...(name ? ["-n", name] : []), ...(effort ? ["--effort", effort] : [])];

// frame(view, title, body): the popup look of the board mods.
export function frame(view, title, body) {
  const t = theme();
  return v_flex().id("at-popup").track_focus(view.handle).on_key_down((e, cx) => view.key(e, cx))
    .w_full().min_h(0).p(18).gap(8).bg(t.popover).text_color(t.foreground).text_size(13)
    .child(h_flex().items_center()
      .child(div().flex_1().text_size(15).font_semibold().child(title))
      .child(div().text_size(11).text_color(t.dim).child("Esc")))
    .children(body)
    .when(Boolean(view.message), (el) => el.child(div().pt(6).text_size(12).text_color(t.muted).child(view.message)));
}

// line(text): one dim text line.
export const line = (text) => div().text_color(theme().muted).child(text);

// input(state): a styled text field.
export const input = (state) => {
  const t = theme();
  return Input.new(state).h(34).px(10).rounded(8).border_1().border_color(t.input).bg(t.background).text_size(13);
};

// QUESTIONS: the text of each step.
export const QUESTIONS = {
  effort: "Effort [l]ow [m]edium [h]igh [x]high [M]ax (Enter for default)",
  focus: "Focus the new tab? [y/N]",
};
