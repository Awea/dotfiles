.PHONY: prezto_install prezto_save tmux_install tmux_save sublimetext_install sublimetext_save zsh_install zsh_save help
.DEFAULT_GOAL := help

DATE := $(shell date +'%F %H:%M')

prezto_install: ## install prezto configuration files
	@cp prezto/source.zpreztorc ~/.zpreztorc
	@echo "prezto installed"

prezto_save: ## save prezto configuration files
	@cp ~/.zpreztorc prezto/source.zpreztorc
	@git add prezto/source.zpreztorc prezto/README.md
	@git commit -m 'update tmux - $(DATE)'
	@git push
	@echo 'prezto saved'

tmux_install: ## install tmux configuration files
	@cp tmux/tmux.conf ~/.tmux.conf
	@cp tmux/tmux.conf.local ~/.tmux.conf.local
	@echo 'tmux installed'

tmux_save: ## save tmux configuration files
	@cp ~/.tmux.conf tmux/tmux.conf 
	@cp ~/.tmux.conf.local tmux/tmux.conf.local
	@git add tmux/*
	@git commit -m 'update tmux - $(DATE)'
	@git push 
	@echo 'tmux saved'

sublimetext_install: ## install sublimetext configuration files
	@cp sublimetext/*.sublime-settings ~/.config/sublime-text-3/Packages/User/
	@cp sublimetext/Default\ \(Linux\).sublime-keymap ~/.config/sublime-text-3/Packages/User/
	@echo 'sublimetext installed'

sublimetext_save: ## save sublimetext configuration files
	@cp ~/.config/sublime-text-3/Packages/User/Default\ \(Linux\).sublime-keymap sublimetext/
	@cp ~/.config/sublime-text-3/Packages/User/*.sublime-settings sublimetext/
	@git add sublimetext/*.sublime-settings sublimetext/*.sublime-keymap sublimetext/README.md
	@git commit -m 'update sublimetext - $(DATE)'
	@git push 
	@echo 'sublimetext saved'

zsh_install: ## install zsh configuration files
	@cp zsh/source.zshrc ~/.zshrc
	@echo 'zsh installed'

zsh_save: ## save zsh configuration files
	@cp ~/.zshrc zsh/source.zshrc
	@git add zsh/source.zshrc zsh/README.md zsh/david.zsh-theme
	@git commit -m 'update zsh - #{time()}'
	@git push
	@echo 'zsh saved'

git_install: ## install git configuration
	@cp git/config ~/.gitconfig
	@echo "git installed"

git_save: ## save git configuration
	@cp ~/.gitconfig git/config
	@git add git/config
	@git commit -m 'update zsh - #{time()}'
	@git push
	@echo "git saved"

all_install: prezto_install tmux_install sublimetext_install zsh_install ## install all configuration files

all_save: prezto_save tmux_save sublimetext_save zsh_save ## save all configuration files

help: ## Print this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'