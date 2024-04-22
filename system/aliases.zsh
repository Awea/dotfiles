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
alias auto-update="topgrade --disable nix rustup cargo flutter composer containers"

# Sublime
alias subl='/opt/sublime_text/sublime_text'
alias smerge='/opt/sublime_merge/sublime_merge'
