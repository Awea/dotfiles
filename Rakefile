namespace :get do
  task :zsh  do
    system 'cp ~/.zshrc $PWD/zsh/source.zshrc'
    p 'zsh getted'
  end
end
namespace :install do
  task :zsh do
    system 'cp $PWD/zsh/source.zshrc ~/.zshrc'
    p 'zsh installed'
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
end