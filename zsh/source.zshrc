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

# Customize to your needs...
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

export NVM_DIR="/home/awea/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm

export PATH=${PATH}:/home/awea/.android-sdk/tools
export PATH=${PATH}:/home/awea/.android-sdk/platform-tools

export ANDROID_HOME="/home/awea/.android-sdk/"

# Local bin
export PATH="$HOME/.local/bin:$PATH"

alias npm-exec='PATH=$(npm bin):$PATH'
alias streamaudio='pulseaudio-dlna'
alias localtunnel='ngrok'

# Vagrant aliases
alias vdf="vagrant destroy -f"
alias vup="vagrant up"
alias vre="vdf && vup"
alias vba="vagrant package --base"

# Firefox
# alias speedfox="find /Users/awea/Library/Application\ Support/Firefox/Profiles/p9yqrvld.default -name '*.sqlite' -print0 | xargs -0 -I{} sqlite3 {} vacuum"

# Fuck
eval "$(thefuck --alias)"

# adminer
alias adminer="sudo php -S localhost:666 ~/.apps/adminer/adminer-4.2.3.php"

# Chrome apps
alias signal="chromium-browser --app-id=bikioccmkafdpakkkcpdbppfkghcmihk"
alias postman="chromium-browser --app-id=fhbjgbiflinjbdggehcddcbncdddomop"