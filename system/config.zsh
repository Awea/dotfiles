# Configure default editor to Sublime Text
# -n = in a new window
# -w = tell command line to wait until document is saved and closed
export EDITOR="/usr/bin/subl -n -w"

# Enable history for iex session
export ERL_AFLAGS="-kernel shell_history enabled"
