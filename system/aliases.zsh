## ls
alias ll='ls -l'
# exa - https://github.com/ogham/exa
alias la="exa -abghl --git --color=automatic"

## Copy to clipboard (pbcopy because I member it from OS X times)
alias pbcopy="xsel -ib"

## Zsh
alias reload!='exec "$SHELL" -l'

## Vagrant aliases
alias vdf="vagrant destroy -f"
alias vup="vagrant up"
alias vre="vdf && vup"
alias vba="vagrant package --base"

# Topgrade! aliases
alias auto-update="topgrade --yes flatpak snap system config_update firmware --disable nix rustup cargo flutter composer containers asdf git_repos pnpm gcloud"

# Thyme aliases
alias track="while true; do thyme track -o $DOTFILES/thyme.json; sleep 30s; done;"
alias track-new="rm -f $DOTFILES/thyme.json; track;"
alias track-display="thyme show -i $DOTFILES/thyme.json -w stats > /tmp/thyme.html; firefox /tmp/thyme.html"
