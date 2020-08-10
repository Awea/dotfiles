# Find all the files/folders ending with .symlink
files_to_symlink := $(shell find . -name '*.symlink')
# Extract just the name.symlink from the previous list
symlinks := $(patsubst %.symlink, %, $(shell basename -a $(files_to_symlink)))
# Generate the complete list of symlink target we need
symlink_paths := $(addprefix $(HOME)/., $(symlinks))

# VPATH tells Make to search this list of folders when using the % pattern
# Documentation: https://www.gnu.org/software/make/manual/html_node/General-Search.html
VPATH = $(shell dirname $(files_to_symlink))

## Create symbolic links for files/folders with a .symlink suffix
.PHONY: links
links: $(symlink_paths) $(HOME)/.config/sublime-merge/Packages/User $(HOME)/.config/sublime-text-3/Packages/User antibody/zsh_plugins.sh

# Create all symlink
# Documentation: https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html#Automatic-Variables
$(HOME)/.%: %.symlink
	ln -s $(abspath $<) $@

$(HOME)/.config/sublime-merge/Packages/User:
	ln -s $(PWD)/sublime-merge $@

$(HOME)/.config/sublime-text-3/Packages/User:
	ln -s $(PWD)/sublime-text-3 $@

antibody/zsh_plugins.sh: antibody/zsh_plugins.txt
	antibody bundle < $< > $@

define primary
\033[38;2;166;204;112;1m$(1)\033[0m
endef

define title
\033[38;2;255;204;102m$(1)\033[0m\n
endef

.DEFAULT_GOAL := help
## List available commands
.PHONY: help
help:
	@printf "$(call primary,dotfiles)\n"
	@printf "My local configuration\n\n"
	@printf "$(call title,USAGE)"
	@printf "    make <SUBCOMMAND>\n\n"
	@printf "$(call title,SUBCOMMANDS)"
	@awk '{ \
		line = $$0; \
		while((n = index(line, "http")) > 0) { \
			if (match(line, "https?://[^ ]+")) { \
			  url = substr(line, RSTART, RLENGTH); \
			  sub(url, "\033[38;2;119;168;217m"url"\033[0m", $$0);  \
			  line = substr(line, n + RLENGTH); \
			} else {\
				break; \
			} \
		}\
		\
		if ($$0 ~ /^.PHONY: [a-zA-Z0-9]+$$/) { \
			helpCommand = substr($$0, index($$0, ":") + 2); \
			if (helpMessage) { \
				printf "    $(call primary,%-8s)%s\n", \
					helpCommand, helpMessage; \
				helpMessage = ""; \
			} \
		} else if ($$0 ~ /^[a-zA-Z\-\_0-9.]+:/) { \
			helpCommand = substr($$0, 0, index($$0, ":")); \
			if (helpMessage) { \
				printf "    $(call primary,%-8s)%s\n", \
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
