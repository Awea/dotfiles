#!/bin/zsh

set -o errexit
set -o nounset
set -o pipefail

[[ "$(uname)" == Linux ]] || { echo "Skip: Linux only"; exit 0; }

# Give Renux the look of herdr-app: the graphite theme, Fira Code at the herdr-app size,
# no ligatures, the padding of the main-quiet layout, the tabs above the panes. A tab
# shows its name, not the programs of its panes. And no system notification, as the
# quiet-toast mod of main-quiet.
# A ctrl+click on a path opens the file in a new pane with bin.symlink/renux-open: a
# markdown file rendered in md-tui, another file in Fresh. config/nix/home.nix installs
# both. The peek button, seen only for a slow file, reads "Open in renux-open".
# settings.ini also keeps the state of Renux (hosts, recent folders), so this script sets
# only its own keys and keeps the other lines. A running Renux reads the file again when
# it changes.
#
# herdr-app draws Fira Code at 14 px with zoom 1.2: 16.8 px. Pango sizes are points, and
# 12.6 pt is 16.8 px at 96 dpi. herdr-app draws heavier strokes than Renux: the Medium
# face of Fira Code in Renux has about the same ink as the Regular face in herdr-app.
settings="${XDG_CONFIG_HOME:-$HOME/.config}/renux/settings.ini"
theme="${XDG_CONFIG_HOME:-$HOME/.config}/renux/themes/herdr-graphite"

mkdir -p "${settings:h}"
touch "$settings"

python3 -I - "$settings" \
  "theme=file:$theme" \
  "theme-follow-system=false" \
  "font=Fira Code Medium 12.6" \
  "ligatures=false" \
  "improve-contrast=false" \
  "selection-bg=$((16#394454))" \
  "selection-fg=$((16#d2d4d9))" \
  "padding-x=14" \
  "padding-y=12" \
  "tab-position=above" \
  "tab-processes=false" \
  "alerts=false" \
  "editor-command=renux-open view {line} {path}" <<'EOF'
import sys

path, pairs = sys.argv[1], [a.split("=", 1) for a in sys.argv[2:]]
lines = open(path).read().splitlines()
if "[renux]" not in lines:
    lines = ["[renux]"] + lines
start = lines.index("[renux]") + 1
end = next((i for i in range(start, len(lines)) if lines[i].startswith("[")), len(lines))
group = [l for l in lines[start:end] if l.split("=", 1)[0] not in dict(pairs)]
while group and group[-1] == "":
    group.pop()
group += [f"{k}={v}" for k, v in pairs]
lines[start:end] = group + ([""] if end < len(lines) else [])
open(path, "w").write("\n".join(lines) + "\n")
EOF

echo "Set the Renux look in $settings"
