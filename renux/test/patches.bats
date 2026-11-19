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
