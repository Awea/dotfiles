#!/bin/fish

export DOTFILES="$HOME/.workspace/dotfiles"

# set fpath ($DOTFILES/functions $fpath)
fish_add_path $DOTFILES/functions

# for topic_folder in $DOTFILES/*
#   if test -d "$topic_folder"
#     set fpath ($topic_folder $fpath)
#   end
# end
