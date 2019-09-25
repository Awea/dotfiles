# Find all the file/folder ending with .symlink
files_to_symlink := $(shell find . -name '*.symlink')
# Extract just the name.symlink from the previous list
symlinks := $(patsubst %.symlink, %, $(shell basename -a $(files_to_symlink)))
# Generate the complete list of symlink target we need
symlink_paths := $(addprefix $(HOME)/., $(symlinks))

# All directory to search for *.symlink files/folder
dir := $(shell find . -type d -not -path '*/\.*')
# VPATH tell make to search this list of folder when using the % pattern
VPATH = $(dir)

install: $(symlink_paths) $(HOME)/.config/sublime-text-3/Packages/User ## Install all configuration files

# Create all symlink
$(HOME)/.%: %.symlink
	ln -s $(abspath $<) $@

$(HOME)/.config/sublime-text-3/Packages/User:
	ln -s $(PWD)/sublime-text-3 $@

.PHONY: help
.DEFAULT_GOAL := help
help: ## Print this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
