# Dev
## Android - https://developer.android.com/studio/#downloads
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/tools:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

## PHP Composer
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

## $HOME/.bin -> $DOTFILES/bin.symlink
export PATH="$HOME/.bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# asdf
export ASDF_DATA_DIR="$HOME/.asdf"
export PATH="$ASDF_DATA_DIR/shims:$PATH"
