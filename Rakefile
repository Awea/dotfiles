namespace :get do
  task :zsh  do
    system 'sh zsh/zsh.sh'
    p 'zsh getted'
  end
end
namespace :push do
  time_o = Time.new
  time = time_o.strftime('%Y-%m-%d %H-%M')

  task :zsh do
    system %{
      git add zsh/source.zshrc zsh/README.md david.zsh-theme
      git commit -m 'update zsh - #{time}'
      git push
    }
    p 'zsh pushed'
  end
end