#!/usr/bin/env bats
# Tests of the Renux patches and of look.sh.
# Run: ASDF_BATS_VERSION=1.8.2 bats renux/test/
# shellcheck disable=SC2030,SC2031 # Each test sets its own env: bats runs each test in a subshell.

setup() {
  repo="$BATS_TEST_DIRNAME/../.."
  src="$HOME/.local/src/renux"
  rev=$(sed -n 's/^renux_rev=//p' "$repo/scripts/programs/renux")
}

@test "each patch applies to the pinned Renux commit" {
  git -C "$src" cat-file -e "$rev^{commit}" 2>/dev/null || skip "no Renux source at $rev"
  tree="$BATS_TEST_TMPDIR/renux"
  mkdir -p "$tree"
  git -C "$src" archive "$rev" | tar -x -C "$tree"
  for p in "$repo"/renux/patches/*.patch; do
    git -C "$tree" apply --check "$p"
    git -C "$tree" apply "$p"
  done
}

@test "the build script applies the patches on a clean checkout" {
  grep -qF 'checkout --quiet --detach --force "$renux_rev"' "$repo/scripts/programs/renux"
  grep -qF 'git -C "$src_dir" apply "$patch"' "$repo/scripts/programs/renux"
}

@test "look.sh turns off the process list in tabs and keeps the other keys" {
  [ "$(uname)" = Linux ] || skip "look.sh runs on Linux only"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/renux"
  printf '[renux]\nwelcomed=true\ntab-processes=true\n' >"$XDG_CONFIG_HOME/renux/settings.ini"
  run "$repo/renux/look.sh"
  [ "$status" -eq 0 ]
  grep -qx 'tab-processes=false' "$XDG_CONFIG_HOME/renux/settings.ini"
  ! grep -qx 'tab-processes=true' "$XDG_CONFIG_HOME/renux/settings.ini"
  grep -qx 'welcomed=true' "$XDG_CONFIG_HOME/renux/settings.ini"
}

@test "look.sh puts the tabs in the sidebar, not above the panes" {
  [ "$(uname)" = Linux ] || skip "look.sh runs on Linux only"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/renux"
  printf '[renux]\ntab-position=above\n' >"$XDG_CONFIG_HOME/renux/settings.ini"
  run "$repo/renux/look.sh"
  [ "$status" -eq 0 ]
  grep -qx 'tab-position=left' "$XDG_CONFIG_HOME/renux/settings.ini"
  ! grep -qx 'tab-position=above' "$XDG_CONFIG_HOME/renux/settings.ini"
}

@test "a sidebar tab row shows the tab label before the title of its open pane" {
  p="$repo/renux/patches/tab-label.patch"
  grep -qF '     pub fn rowTitle(h: *Host, buf: []u8, w: *const view.Window, v: *const view.SessionView) [:0]const u8 {' "$p"
  grep -qxF '+        if (w.title()) |t| return std.fmt.bufPrintSentinel(buf, "{s}", .{t}, 0) catch "Window";' "$p"
  grep -qxF -e '-        if (w.title()) |t| return std.fmt.bufPrintSentinel(buf, "{s}", .{t}, 0) catch "Window";' "$p"
}

@test "look.sh opens the peek file with renux-open" {
  [ "$(uname)" = Linux ] || skip "look.sh runs on Linux only"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  run "$repo/renux/look.sh"
  [ "$status" -eq 0 ]
  grep -qx 'editor-command=renux-open view {line} {path}' "$XDG_CONFIG_HOME/renux/settings.ini"
}

@test "the pane title has the size of the tab label" {
  grep -qF '+    \\.pane-title .title { font-weight: 500; font-size: 1em; }' "$repo/renux/patches/pane-title-size.patch"
}

@test "the pane title does not repeat the tab name" {
  p="$repo/renux/patches/pane-title-not-tab-name.patch"
  grep -qF '+        if (v.server.sessionView(v.session_id)) |sv| if (sv.windowOf(v.block_id)) |w| if (w.title()) |name| {' "$p"
  grep -qF '+            if (std.mem.eql(u8, name, t)) t = v.programTitle(&pbuf);' "$p"
}

@test "the sidebar shows the summary sentence and a state emoji" {
  p="$repo/renux/patches/sidebar-status.patch"
  grep -qF '+                    if (json.str(rec, "id")) |id| if (eql(id, "summary")) {' "$p"
  grep -qF '+            const said = if (status == .blocked or status == .failed) word else (summary orelse word);' "$p"
  grep -qF '+                l.as(gtk.Widget).addCssClass("status-emoji");' "$p"
}

@test "a click on the pane title copies the pane ID" {
  p="$repo/renux/patches/title-click-copies-pane-id.patch"
  grep -qF '+            .{ "pane-copy-id", copyPaneId },' "$p"
  grep -qF '+        a.toast("Pane ID copied");' "$p"
  grep -qF '+        label.as(gtk.Widget).addController(title_click.as(gtk.EventController));' "$p"
  grep -qF '+        text.getLayoutOffsets(&text_x, null);' "$p"
  grep -qF '+        app.as(gio.ActionGroup).activateAction("pane-copy-id", glib.Variant.newString(block.ptr));' "$p"
}

@test "a Ctrl-click on a renux://block/ link shows the pane of that block" {
  p="$repo/renux/patches/block-link.patch"
  grep -qF '+pub const block_prefix = "renux://block/";' "$p"
  grep -qF '+        if (links.blockId(url)) |id| return v.openBlock(id);' "$p"
  grep -qF '+        return links.blockId(url) != null or isFileLink(url);' "$p"
  grep -qF '+test "a block link stays with Renux, and the menu does not call it a file"' "$p"
  grep -qF '+            .{ "jump-block", jumpBlock },' "$p"
  grep -qF '+test "a renux block link names a block, not a file"' "$p"
}

@test "a Ctrl-click on a web link opens it at once, also in a pane that takes the mouse" {
  p="$repo/renux/patches/web-link-opens-at-once.patch"
  grep -qF '+        return keepsClick(url) or v.linksOpenHere() or v.keepsWebLink(url);' "$p"
  grep -qF '+                    armed = !t.frame.mouse or v.linksOpenHere() or keepsClick(url) or v.keepsWebLink(url);' "$p"
  grep -qF '+test "a ctrl+click on a web link is kept from a program on this computer" {' "$p"
}

@test "the wheel over a full-screen program without the mouse sends arrow keys" {
  p="$repo/renux/patches/wheel-arrows-without-mouse.patch"
  grep -qF '+            if (!t.frame.mouse) {' "$p"
  grep -qF '+                v.sendWheelArrows(steps, if (following) 1 else presses_a_step);' "$p"
  grep -qF '+            v.wheelToProgram(t, if (surface) dy * settings.current.scroll_speed / v.cell_h else dy, mods, if (surface) 1 else 3);' "$p"
  grep -qF '+test "the wheel over a full-screen program without the mouse sends arrow keys" {' "$p"
}

@test "the current sidebar row has an accent tint, a left bar and a bold title" {
  p="$repo/renux/patches/sidebar-current-row.patch"
  grep -qF '+    \\.renux-sidebar list > row:selected:not(.session-pick) { background-color: alpha(@accent_bg_color, 0.22); box-shadow: inset 3px 0 0 @accent_bg_color, 0 1px 3px alpha(black, 0.14); }' "$p"
  grep -qF '+    \\.renux-sidebar list > row:selected:focus-visible:not(.session-pick) { background-color: alpha(@accent_bg_color, 0.22); }' "$p"
  grep -qF '+    \\.renux-sidebar list > row:selected .row-title { font-weight: 700; }' "$p"
  grep -qF '+    \\window.tight .renux-sidebar list > row:selected:not(.session-row) { box-shadow: inset 3px 0 0 @accent_bg_color; }' "$p"
}

@test "the subtext of a sidebar agent row has the size that GTK draws whole" {
  p="$repo/renux/patches/sidebar-subtext-size.patch"
  grep -qxF -e '-    \\.agent-status { font-size: 0.86em; color: @renux_secondary; }' "$p"
  grep -qxF '+    \\.agent-status { font-size: 0.9em; color: @renux_secondary; }' "$p"
}

@test "a drag motion tells Rex that its button is held" {
  p="$repo/renux/patches/drag-motion-holds-button.patch"
  grep -qF '+            .buttons = heldButtons(action, button),' "$p"
  grep -qF '+        return .{ .name = button, .pressed = !eql(action, "release") };' "$p"
  grep -qF '+test "a drag motion tells Rex that its button is held" {' "$p"
}

@test "the eye lists agents, and not a program such as Leaf that reports a status" {
  p="$repo/renux/patches/eye-lists-only-agents.patch"
  grep -qF '+    return isAgent(process) or isAgent(status_app);' "$p"
  grep -qF '+                    if (!programs.listsAsAgent(info.program, if (info.has_status) info.status_app else null)) continue;' "$p"
  grep -qF '+test "the eye lists agents, and not a program that reports a status" {' "$p"
}
