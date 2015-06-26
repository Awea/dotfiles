#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Aliases
alias rake="noglob rake"
alias blitz="noglob blitz"
alias cutest="nocorrect cutest"
alias rspec="nocorrect rspec"
alias pass="nocorrect pass"

# Osx related
alias chrome_ext='cd ~/Library/Application\ Support/Google/Chrome/Default'
alias osx_apache='sudo apachectl'
alias flushme='sudo purge'
alias py='python'

# Osx 10.7.5
alias dock_crash='killall -KILL Dock'
alias finder_crash='killall -KILL Finder'

# Ruby aliases
alias rbr="rbenv rehash"

# Vagrant aliases
alias vdf="vagrant destroy -f"
alias vup="vagrant up"
alias vre="vdf && vup"
alias vba="vagrant package --base"

# Ansible export
export ANSIBLE_HOSTS=~/ansible_hosts

# Electron caca
alias electron="/opt/homebrew-cask/Caskroom/electron/0.25.3/Electron.app/Contents/MacOS/Electron"

# Thefuck
alias fuck='eval $(thefuck $(fc -ln -1)); history -r'

# Git
alias git=hub

# Go
export GOPATH=$HOME/.go
export PATH=$PATH:$GOPATH/bin

# Firefox
alias speedfox="find /Users/awea/Library/Application\ Support/Firefox/Profiles/p9yqrvld.default -name '*.sqlite' -print0 | xargs -0 -I{} sqlite3 {} vacuum"

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/git/bin:/opt/local/bin"
export EDITOR=sublw
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

export PATH="$PATH:/Users/awea/bin"