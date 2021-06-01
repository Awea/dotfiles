# Git
# Source: https://github.com/sorin-ionescu/prezto/blob/master/modules/git/alias.zsh
alias g='git'

# Commit (c)
alias gcm='git commit --message'

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

# Branches
## Remove merged branch from a Git repository
## Inspiration: https://gist.github.com/TBonnin/4060788
alias gR='git branch --merged master | grep -v 'master$' | xargs git branch -d'
