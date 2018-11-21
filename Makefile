.PHONY: prezto_install prezto_save tmux_install tmux_save subl_install subl_save zsh_install zsh_save git_install git_save all_install all_save help
.DEFAULT_GOAL := help

prezto_install: ## Install Prezto configuration files
	@cp prezto/source.zpreztorc ~/.zpreztorc
	@echo '👍 Prezto installed'

prezto_save: ## Save Prezto configuration files
	@cp ~/.zpreztorc prezto/source.zpreztorc
	@git add prezto
	@git commit -m '🔧 Update Prezto'
	@git push
	@echo '💾 Prezto saved'

tmux_install: ## Install Tmux configuration files
	@cp tmux/tmux.conf ~/.tmux.conf
	@echo '👍 Tmux installed'

tmux_save: ## Save Tmux configuration files
	@cp ~/.tmux.conf tmux/tmux.conf
	@git add tmux
	@git commit -m '🔧 Update Tmux'
	@git push 
	@echo '💾 Tmux saved'

subl_install: ## Install Sublime Text configuration files
	@cp sublimetext/*.sublime-settings ~/.config/sublime-text-3/Packages/User/
	@cp sublimetext/Default\ \(Linux\).sublime-keymap ~/.config/sublime-text-3/Packages/User/
	@echo '👍 Sublime Text installed'

subl_save: ## Save Sublime Text configuration files
	@cp ~/.config/sublime-text-3/Packages/User/Default\ \(Linux\).sublime-keymap sublimetext/
	@cp ~/.config/sublime-text-3/Packages/User/*.sublime-settings sublimetext/
	@git add sublimetext
	@git commit -m '🔧 Update Sublime Text'
	@git push 
	@echo '💾 Sublime Text saved'

zsh_install: ## Install Zsh configuration files
	@cp zsh/source.zshrc ~/.zshrc
	@echo '👍 Zsh installed'

zsh_save: ## Save Zsh configuration files
	@cp ~/.zshrc zsh/source.zshrc
	@git add zsh
	@git commit -m '🔧 Update Zsh'
	@git push
	@echo '💾 Zsh saved'

git_install: ## Install Git configuration
	@cp git/config ~/.gitconfig
	@echo '👍 Git installed'

git_save: ## Save Git configuration
	@cp ~/.gitconfig git/config
	@git add git/config
	@git commit -m '🔧 Update Git'
	@git push
	@echo '💾 Git saved'

all_install: prezto_install tmux_install subl_install zsh_install git_install ## Install all configuration files

all_save: prezto_save tmux_save subl_save zsh_save git_save ## Save all configuration files

help: ## Print this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
