# Configure default editor to Sublime Text
# -n = in a new window
# -w = tell command line to wait until document is saved and closed
# subl is /usr/bin/subl on Linux and /opt/homebrew/bin/subl on macOS: find it in PATH.
export EDITOR="subl -n -w"

# Enable history for iex session
export ERL_AFLAGS="-kernel shell_history enabled"

# Let unprivileged users use the nix-daemon
# https://nixos.org/manual/nix/stable/installation/multi-user.html
export NIX_REMOTE=daemon

# Characters considered part of a word
export WORDCHARS="*?_-.[]~=&;!#$%^(){}<>"
