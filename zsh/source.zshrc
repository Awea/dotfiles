if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  . "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Misc

## z - https://github.com/rupa/z
. $HOME/.apps/z.sh

# Dev 

## Asdf - https://github.com/asdf-vm/asdf
. $HOME/.asdf/asdf.sh
. $HOME/.asdf/completions/asdf.bash

## Rust > Cargo
export PATH="$HOME/.cargo/bin:$PATH"

# mix auto-completion (Elixir) - https://github.com/dalexj/mix_autocomplete
# . $HOME/.apps/mix_autocomplete/mix_autocomplete.zsh

# Aliases

## Vagrant aliases
alias vdf="vagrant destroy -f"
alias vup="vagrant up"
alias vre="vdf && vup"
alias vba="vagrant package --base"

## Kill a processus by it's port
function killp {
  kill -9 $( lsof -i:$1 -t ) 
}

## Adminer - https://www.adminer.org/
alias adminer="php -S localhost:4666 -t ~/.apps/adminer/"

## Git webui - https://github.com/alberthier/git-webui
alias gui="ASDF_PYTHON_VERSION=2.7.12 git webui --no-browser"

# exa - https://github.com/ogham/exa
alias la="exa -abghl --git --color=automatic"