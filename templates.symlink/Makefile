#@name Project name
#@description Project description.

# Use one shell for the whole recipe, instead of per-line
.ONESHELL:
# Use bash in strict mode
SHELL := bash
.SHELLFLAGS = -eu -o pipefail -c

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
	@bin/pretty-make pretty-help Makefile
