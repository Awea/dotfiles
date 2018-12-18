if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  . "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Misc
## z - https://github.com/rupa/z
. $HOME/.apps/z.sh

## Completion
fpath=(~/.zsh/completion $fpath)
autoload -Uz compinit && compinit -i

# Dev
## Android - https://developer.android.com/studio/#downloads
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/tools:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH" 

## Asdf - https://github.com/asdf-vm/asdf
. $HOME/.asdf/asdf.sh
. $HOME/.asdf/completions/asdf.bash

## Rust > Cargo
export PATH="$HOME/.cargo/bin:$PATH"

## Go
export PATH="$HOME/go/bin:$PATH"

## PHP > Composer
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

## local/sbin 
export PATH="/usr/local/sbin:$PATH"

## $HOME/bin
export PATH="$HOME/bin:$PATH"

# Aliases

## Docker aliases
### WP-CLI
alias dcwp='docker-compose exec --user www-data phpfpm wp'

## Vagrant aliases
alias vdf="vagrant destroy -f"
alias vup="vagrant up"
alias vre="vdf && vup"
alias vba="vagrant package --base"

## Yarn
alias yarn-exec="PATH=$(yarn bin):$PATH"

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

# Restart audio
alias restart-audio="pulseaudio -k && sudo alsa force-reload"
