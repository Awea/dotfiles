#@name Project name
#@description Project description.

# Here we ensure that every command this Makefile run will run in a bash shell
# instead of the default sh
# See https://tech.davis-hansson.com/p/make
SHELL := /usr/bin/env bash

.PHONY: deps
deps: node_modules

node_modules: package.json yarn.lock
	@yarn install
	@touch $@

bin/pretty-make:
	@curl -Ls https://raw.githubusercontent.com/awea/pretty-make/master/scripts/install.sh | bash -s

.DEFAULT_GOAL := help
.PHONY: help
## List available commands
help: bin/pretty-make
	@bin/pretty-make Makefile
