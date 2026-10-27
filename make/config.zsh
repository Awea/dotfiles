#! /usr/bin/env zsh

# MAKEFLAGS to define make default flags, on macOS only:
# - `-j 8` number of simultaned jobs
# - `--no-print-directory` obviously
if [[ "$(uname)" == Darwin ]]; then
  export MAKEFLAGS='-j 8 --no-print-directory' # -s'
fi
