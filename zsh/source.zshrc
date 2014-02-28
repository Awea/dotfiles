# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

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

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how many often would you like to wait before auto-updates occur? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(git pass)

source $ZSH/oh-my-zsh.sh
#source /usr/local/etc/bash_completion.d/password-store ? wtf

# Customize to your needs...
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/X11/bin:/usr/local/git/bin:/usr/local/go/bin

export EDITOR=subl
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

### Rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

### Golang
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

### Webboob
export PATH="$PATH:/Users/aweaoftheworld/bin"

### Ansible
export ANSIBLE_HOSTS="$HOME/ansible_hosts"