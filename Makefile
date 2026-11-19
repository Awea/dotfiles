# Find all the files/folders ending with .symlink
files_to_symlink := $(shell find . -name '*.symlink')
# Extract just the name.symlink from the previous list
symlinks := $(patsubst %.symlink, %, $(shell basename -a $(files_to_symlink)))
# Generate the complete list of symlink target we need
symlink_paths := $(addprefix $(HOME)/., $(symlinks))

# VPATH tells Make to search this list of folders when using the % pattern
# Documentation: https://www.gnu.org/software/make/manual/html_node/General-Search.html
VPATH = $(shell dirname $(files_to_symlink))

# Sublime Text/Merge keep their user packages in ~/Library on macOS
ifeq ($(shell uname),Darwin)
os := macos
sublime_links := sublime-links
# Antibody is archived and gone from Homebrew; antidote reads the same plugin list
bundle_plugins := zsh -c 'source $$(brew --prefix antidote)/share/antidote/antidote.zsh && antidote bundle'
else
os := linux
sublime_links := $(HOME)/.config/sublime-merge/Packages/User $(HOME)/.config/sublime-text/Packages/User
bundle_plugins := antibody bundle
endif

## Create symbolic links for files/folders with a .symlink suffix
.PHONY: links
links: $(symlink_paths) $(sublime_links) antibody/zsh_plugins.sh $(HOME)/.config/direnv $(HOME)/.config/nix config/nix/os.conf $(HOME)/.config/zed/settings.json $(HOME)/.config/zed/keymap.json $(HOME)/.config/fresh/config.json $(HOME)/.config/fresh/themes/herdr-graphite.json $(HOME)/.claude/CLAUDE.md $(HOME)/.claude/rules/elixir.md $(HOME)/.claude/settings.json $(HOME)/.claude/agents/reviewer.md $(HOME)/.claude/hooks/plugin-skill-overrides.sh $(HOME)/.config/ghostty/config.ghostty $(HOME)/.config/ghostty/os.ghostty $(HOME)/.claude/skills/handoff $(HOME)/.claude/skills/ste-writing $(HOME)/.claude/skills/writing-for-agents $(HOME)/.claude/skills/retro $(HOME)/.claude/skills/project-tool-check $(HOME)/.claude/skills/board-orchestrator

# Create all symlink
# Documentation: https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html#Automatic-Variables
$(HOME)/.%: %.symlink
	ln -s $(abspath $<) $@

$(HOME)/.config/sublime-merge/Packages/User:
	ln -s $(PWD)/sublime-merge $@

$(HOME)/.config/sublime-text/Packages/User:
	ln -s $(PWD)/sublime-text-3 $@

# macOS: the scripts replace the default User folder with a link to this repo
# They wait for the user with read, and make -j (MAKEFLAGS on macOS) gives the input
# to one job only: run all recipes one at a time.
.NOTPARALLEL:
.PHONY: sublime-links
sublime-links:
	./scripts/symlinks/sublime-merge
	./scripts/symlinks/sublime-text

# nix.conf reads os.conf: the settings of this OS only, such as auto-optimise-store.
# ~/.config/nix links to config/nix, so the link is in the repo (git-ignored).
config/nix/os.conf:
	ln -s $(os).conf $@

$(HOME)/.config/zed/settings.json:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/zed/settings.json $@

$(HOME)/.config/zed/keymap.json:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/zed/keymap.json $@

# Fresh, the editor of the Renux file peek: link only config.json. Fresh keeps its
# themes and plugins in the same folder. A setting changed in Fresh replaces the link
# with a file: copy that file to config/fresh, remove it and run make links again.
$(HOME)/.config/fresh/config.json:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/config/fresh/config.json $@

# The herdr-graphite theme of Fresh: the terminal colors of Renux, and its selection color
$(HOME)/.config/fresh/themes/herdr-graphite.json:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/config/fresh/themes/herdr-graphite.json $@

$(HOME)/.claude/CLAUDE.md:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/CLAUDE.md $@

$(HOME)/.claude/rules/elixir.md:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/rules/elixir.md $@

$(HOME)/.claude/settings.json:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/settings.json $@

$(HOME)/.claude/agents/reviewer.md:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/agents/reviewer.md $@

# A SessionStart hook: skillOverrides "user-invocable-only" for plugin entries
$(HOME)/.claude/hooks/plugin-skill-overrides.sh:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/hooks/plugin-skill-overrides.sh $@

$(HOME)/.config/ghostty/config.ghostty:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/ghostty/config.ghostty $@

# config.ghostty reads os.ghostty: the settings of this OS only, such as the font size
$(HOME)/.config/ghostty/os.ghostty:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/ghostty/$(os).ghostty $@

$(HOME)/.claude/skills/handoff:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/skills/handoff $@

$(HOME)/.claude/skills/ste-writing:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/skills/ste-writing $@

$(HOME)/.claude/skills/writing-for-agents:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/skills/writing-for-agents $@

$(HOME)/.claude/skills/retro:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/skills/retro $@

$(HOME)/.claude/skills/project-tool-check:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/skills/project-tool-check $@

$(HOME)/.claude/skills/board-orchestrator:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/claude/skills/board-orchestrator $@

## Link the herdr-app keys, mods, layout and scripts
## (Linux and macOS). A plain keys.json moves to keys.json.before-dotfiles first.
HERDR_APP_HOME ?= $(HOME)/.config/herdr-app
.PHONY: herdr-app
herdr-app:
	@mkdir -p $(HERDR_APP_HOME)/mods $(HERDR_APP_HOME)/layouts $(HOME)/.claude/skills
	@if [ -f $(HERDR_APP_HOME)/keys.json ] && [ ! -L $(HERDR_APP_HOME)/keys.json ]; then \
	  mv $(HERDR_APP_HOME)/keys.json $(HERDR_APP_HOME)/keys.json.before-dotfiles; fi
	ln -sfn $(PWD)/herdr-app/keys.json $(HERDR_APP_HOME)/keys.json
	ln -sfn $(PWD)/herdr-app/layouts/main-quiet.json $(HERDR_APP_HOME)/layouts/main-quiet.json
	ln -sfn $(PWD)/herdr-app/bin $(HERDR_APP_HOME)/bin
	for m in board-open board-stop quiet-toast prefix new-agent-tab handoff new-space claude-resume; do \
	  ln -sfn $(PWD)/herdr-app/mods/$$m $(HERDR_APP_HOME)/mods/$$m; done

## Give Renux, the Linux client of Rex, the herdr-app look and keys: link the Rex config,
## link the graphite theme and set the look keys in settings.ini (Linux only).
RENUX_HOME ?= $(HOME)/.config/renux
.PHONY: renux
renux: $(HOME)/.config/rex
	@mkdir -p $(RENUX_HOME)/themes
	ln -sfn $(PWD)/renux/themes/herdr-graphite $(RENUX_HOME)/themes/herdr-graphite
	renux/look.sh

$(HOME)/.config/%:
	@mkdir -p $(dir $@)
	ln -s $(PWD)/config/$* $@

antibody/zsh_plugins.sh: antibody/zsh_plugins.txt
	$(bundle_plugins) < $< > $@

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
		if ($$0 ~ /^.PHONY: [a-zA-Z0-9_-]+$$/) { \
			helpCommand = substr($$0, index($$0, ":") + 2); \
			if (helpMessage) { \
				printf "    $(call primary,%-14s)%s\n", \
					helpCommand, helpMessage; \
				helpMessage = ""; \
			} \
		} else if ($$0 ~ /^[a-zA-Z\-\_0-9.]+:/) { \
			helpCommand = substr($$0, 0, index($$0, ":")); \
			if (helpMessage) { \
				printf "    $(call primary,%-14s)%s\n", \
					helpCommand, helpMessage; \
				helpMessage = ""; \
			} \
		} else if ($$0 ~ /^##/) { \
			if (helpMessage) { \
				helpMessage = helpMessage "\n                  " substr($$0, 3); \
			} else { \
				helpMessage = substr($$0, 3); \
			} \
		} \
	}' \
	$(MAKEFILE_LIST)
