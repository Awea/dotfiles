def time
  time_o = Time.new
  time_o.strftime('%Y-%m-%d %H-%M')
end

namespace :prezto do
  desc "install prezto configuration files"
  task :install do
    system 'cp prezto/source.zpreztorc ~/.zpreztorc'
    p 'prezto installed'
  end

  desc "save prezto configuration files"
  task :save do
    system %{
      cp ~/.zpreztorc prezto/source.zpreztorc
      git add prezto/source.zpreztorc prezto/README.md 
      git commit -m 'update prezto - #{time()}'
      git push
    }
    p 'prezto saved'
  end
end

namespace :tmux do
  desc "install tmux configuration files"
  task :install do
    system %{
      cp tmux/tmux.conf ~/.tmux.conf
      cp tmux/tmux.conf.local ~/.tmux.conf.local
    }
    p 'tmux installed'
  end

  desc "save tmux configuration files"
  task :save do
    system %{
      cp ~/.tmux.conf tmux/tmux.conf 
      cp ~/.tmux.conf.local tmux/tmux.conf.local
      git add tmux/*
      git commit -m 'update tmux - #{time()}'
      git push 
    }
    p 'tmux saved'
  end
end

namespace :sublimetext do
  desc "install sublimetext configuration files"
  task :install do
    system 'cp sublimetext/*.sublime-settings ~/.config/sublime-text-3/Packages/User/'
    system 'cp sublimetext/Default\ \(Linux\).sublime-keymap ~/.config/sublime-text-3/Packages/User/'
    p 'sublimetext installed'
  end

  desc "save sublimetext configuration files"
  task :save do
    # system using %{} doesn't support escape characters (\).
    system 'cp ~/.config/sublime-text-3/Packages/User/Default\ \(Linux\).sublime-keymap sublimetext/'
    system %{
      cp ~/.config/sublime-text-3/Packages/User/*.sublime-settings sublimetext/
      git add sublimetext/*.sublime-settings sublimetext/*.sublime-keymap sublimetext/README.md 
      git commit -m 'update sublimetext - #{time()}'
      git push 
    }

    p 'sublimetext saved'
  end
end

namespace :zsh do
  desc "install zsh configuration files"
  task :install do
    system 'cp zsh/source.zshrc ~/.zshrc'
    p 'zsh installed'
  end

  desc "save zsh configuration files"
  task :save do
    system %{
      cp ~/.zshrc zsh/source.zshrc
      git add zsh/source.zshrc zsh/README.md zsh/david.zsh-theme
      git commit -m 'update zsh - #{time()}'
      git push
    }
    p 'zsh saved'
  end
end

namespace :all do
  desc "install all configuration files"
  multitask install: ["prezto:install", "sublimetext:install", "zsh:install"]

  desc "save all configuration files"
  task save: ["prezto:save", "sublimetext:save", "zsh:save"]
end
