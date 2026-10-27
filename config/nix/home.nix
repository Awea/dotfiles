{ config, pkgs, lib, inputs, ... }:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
in
{
  home.username = "awea";
  home.homeDirectory = if isDarwin then "/Users/awea" else "/home/awea";

  # Do NOT change after the first install.
  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.stateVersion
  home.stateVersion = "25.11";

  # Let home-manager manage itself.
  programs.home-manager.enable = true;

  # Packages installed here land on $PATH everywhere (via ~/.nix-profile/bin).
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    uv
    codex
    # Apt has tmux 3.2a, too old for OSC 8 hyperlinks (tmux 3.4+).
    tmux
  ] ++ [
    inputs.hunk.packages.${system}.default
  ];

  # macOS has no systemd: these services are Linux only.
  systemd.user = lib.mkIf isLinux {
    # Start/restart changed systemd user services automatically on `switch`.
    startServices = "sd-switch";

    # Free disk space every day, only when / has less than 100G free.
    # The script lives in the dotfiles: bin.symlink/prune-disk.
    services.prune-disk = {
      Unit.Description = "Free disk space when / is low";
      Service = {
        Type = "oneshot";
        ExecStart = "%h/.bin/prune-disk";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    timers.prune-disk = {
      Unit.Description = "Daily disk space check";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };

  # macOS: the same job as a launchd user agent (~/Library/LaunchAgents).
  # Logs go to ~/Library/Logs, there is no journal.
  launchd.agents = lib.mkIf isDarwin {
    # Same schedule as the systemd timer: daily at midnight. launchd runs a
    # missed run on wake, like Persistent=true. Nice + LowPriorityIO match
    # Nice=19 and IOSchedulingClass=idle.
    prune-disk = {
      enable = true;
      config = {
        ProgramArguments = [ "${config.home.homeDirectory}/.bin/prune-disk" ];
        StartCalendarInterval = [ { Hour = 0; Minute = 0; } ];
        ProcessType = "Background";
        Nice = 19;
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/prune-disk.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/prune-disk.log";
      };
    };
  };
}
