#!/bin/zsh

# A Nix program (mosh, tmux) has its own ncurses, which reads only the terminfo
# of its Nix store path. Rex installs xterm-rex in /usr/share/terminfo, so a Nix
# mosh in a Renux pane stops with "'xterm-rex': unknown terminal type".
# The empty first entry keeps the default database of each ncurses (Nix or
# system), then the system directories that exist follow.
() {
  local -a dirs=(${(s.:.)TERMINFO_DIRS} /etc/terminfo(N/) /lib/terminfo(N/) /usr/share/terminfo(N/))
  dirs=(${(u)dirs})
  export TERMINFO_DIRS=":${(j.:.)dirs}"
}
