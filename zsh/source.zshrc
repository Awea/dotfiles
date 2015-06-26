# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="david"

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

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to disable command auto-correction.
# DISABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(git z)

source $ZSH/oh-my-zsh.sh

# User configuration

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/git/bin:/opt/local/bin"
# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Editor
export EDITOR=sublw
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

twister() {
  local origin
  origin=($(pwd))
  cd ~/.in-progress/twister-core
  ./twisterd -daemon
  cd $origin
}

export PATH="$PATH:/Users/awea/bin"
