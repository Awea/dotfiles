# Obsidian vault for the obsidian-second-brain Claude plugin
if [[ "$(uname)" == Darwin ]]; then
  export OBSIDIAN_VAULT_PATH="$HOME/.syncthing/second-brain"
else
  export OBSIDIAN_VAULT_PATH="$HOME/Dropbox/documents/second-brain"
fi
