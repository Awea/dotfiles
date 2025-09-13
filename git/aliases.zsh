# Git
# Source: https://github.com/sorin-ionescu/prezto/blob/master/modules/git/alias.zsh
alias g='git'
alias gc='git clone'

# Commit (c)
alias gcm='git commit --message'
alias gca='git absorb'

# Fetch (f)
alias gfa='git fetch --all'
alias gfr='git pull --rebase'

# Push (p)
alias gp='git push'
alias gpF='git push --force'
alias gpA='git push --all && git push --tags'

# Stash (s)
alias gs='git stash'
alias gsp='git stash pop'

# Rebase (r)
alias gra='git rebase -i --autosquash'

# Branches
## Remove merged branch from a Git repository
## Inspiration: https://gist.github.com/TBonnin/4060788
alias gR='git branch --merged main | grep -v 'main$' | xargs git branch -d'
