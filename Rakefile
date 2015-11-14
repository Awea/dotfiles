namespace :get do
  task :zsh  do
    system 'cp ~/.zshrc $PWD/zsh/source.zshrc'
    p 'zsh getted'
  end

  task :sublimetext do
    system 'cp ~/.config/sublime-text-3/Packages/User/Preferences.sublime-settings $PWD/sublimetext/'
    system 'cp ~/.config/sublime-text-3/Packages/User/Package\ Control.sublime-settings $PWD/sublimetext/'
    system 'cp ~/.config/sublime-text-3/Packages/User/Default\ \(Linux\).sublime-keymap $PWD/sublimetext/'
    p 'sublimetext getted'
  end

  task :terminator do
    system 'cp ~/.config/terminator/config $PWD/terminator/'
    p 'terminator getted'
  end 
end

namespace :install do
  task :zsh do
    system 'cp $PWD/zsh/source.zshrc ~/.zshrc'
    p 'zsh installed'
  end

  task :sublimetext do
    system 'cp $PWD/sublimetext/*.sublime-settings ~/.config/sublime-text-3/Packages/User/'
    system 'cp $PWD/sublimetext/Default\ \(Linux\).sublime-keymap ~/.config/sublime-text-3/Packages/User/'
    p 'sublimetext installed'
  end

  task :terminator do
    system 'cp $PWD/terminator/config ~/.config/terminator/'
    p 'terminator installed'
  end 
end

namespace :push do
  time_o = Time.new
  time = time_o.strftime('%Y-%m-%d %H-%M')

  task :zsh do
    system %{
      git add zsh/source.zshrc zsh/README.md zsh/david.zsh-theme
      git commit -m 'update zsh - #{time}'
      git push
    }
    p 'zsh pushed'
  end

  task :sublimetext do
    system %{
      git add sublimetext/*.sublime-settings sublimetext/*.sublime-keymap sublimetext/README.md 
      git commit -m 'update sublimetext - #{time}'
      git push
    }
    p 'sublimetext pushed'
  end

  task :terminator do
    system %{
      git add terminator/config
      git commit -m 'update terminator - #{time}'
      git push
    }
    p 'terminator pushed'
  end
end