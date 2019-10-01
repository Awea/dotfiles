# Find all the file/folder ending with .symlink
files_to_symlink := $(shell find . -name '*.symlink')
# Extract just the name.symlink from the previous list
symlinks := $(patsubst %.symlink, %, $(shell basename -a $(files_to_symlink)))
# Generate the complete list of symlink target we need
symlink_paths := $(addprefix $(HOME)/., $(symlinks))

# VPATH tell make to search this list of folder when using the % pattern
# Documentation: https://www.gnu.org/software/make/manual/html_node/General-Search.html
VPATH = $(shell dirname $(files_to_symlink))

## Create symbolic link for files and folders with a `.symlink` suffix
.PHONY: links
links: $(symlink_paths) $(HOME)/.config/sublime-text-3/Packages/User

# Create all symlink
# Documentation: https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html#Automatic-Variables
$(HOME)/.%: %.symlink
	ln -s $(abspath $<) $@

$(HOME)/.config/sublime-text-3/Packages/User:
	ln -s $(PWD)/sublime-text-3 $@

define green-bold
\033[38;2;166;204;112;1m$(1)\033[0m
endef

define orange
\033[38;2;255;204;102m$(1)\033[0m\n
endef

.DEFAULT_GOAL := help
## List available commands
.PHONY: help
help:
	@printf "$(call green-bold,dotfiles)\n"
	@printf "David's dotfiles\n\n"
	@printf "$(call orange,USAGE)"
	@printf "    make <SUBCOMMAND>\n\n"
	@printf "$(call orange,SUBCOMMANDS)"
	@awk '{ \
		if ($$0 ~ /^.PHONY: [a-zA-Z\-\_0-9]+$$/) { \
			helpCommand = substr($$0, index($$0, ":") + 2); \
			if (helpMessage) { \
				printf "    $(call green-bold,%-8s)%s\n", \
					helpCommand, helpMessage; \
				helpMessage = ""; \
			} \
		} else if ($$0 ~ /^##/) { \
			if (helpMessage) { \
				helpMessage = helpMessage "\n            " substr($$0, 3); \
			} else { \
				helpMessage = substr($$0, 3); \
			} \
		} \
	}' \
	$(MAKEFILE_LIST)