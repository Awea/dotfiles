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

  # Pin `nixpkgs#...` (as in `nix run nixpkgs#forgejo-mcp`) to the rev of
  # flake.lock. The global registry points to the unstable channel: after the
  # 1 h tarball TTL, a channel update makes nix fetch and evaluate nixpkgs again
  # (about 30 s), and an MCP server start goes past the 30 s Claude Code limit.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # Packages installed here land on $PATH everywhere (via ~/.nix-profile/bin).
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    uv
    codex
    # Apt has tmux 3.2a, too old for OSC 8 hyperlinks (tmux 3.4+).
    tmux
    # Apt has mosh 1.3.2, which drops OSC 52: a copy in a remote tmux does
    # not reach the local clipboard. mosh 1.4 passes it.
    # Nix mosh runs the Nix ssh, which has no GSSAPI and no Apple options: it
    # warns on the GSSAPI line of /etc/ssh/ssh_config, and fails on an Apple
    # option such as UseKeychain. --ssh=ssh runs the ssh of $PATH, the one
    # that a plain `ssh` runs. A later --ssh on the command line wins.
    (symlinkJoin {
      name = "mosh-system-ssh";
      paths = [ mosh ];
      nativeBuildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/mosh --add-flags --ssh=ssh
      '';
    })
    # The editor of the Renux file peek (renux/look.sh): keys as in Sublime
    # Text and VS Code, a file tree and a ctrl+p file finder. Config in
    # config/fresh.
    fresh-editor
    # The markdown view of the Renux file peek (bin.symlink/renux-open): Leaf, the
    # release pinned in leaf.nix. A drag selects text and copies it without the
    # wrap, and @ asks an agent pane about the selection. Config in config/leaf.
    (callPackage ./leaf.nix { })
  ] ++ [
    inputs.hunk.packages.${system}.default
  ];

  # Nix programs find the GPU drivers in /run/opengl-driver, as on NixOS.
  # scripts/programs/nix-home-manager runs the root setup that makes the link.
  # The version must be the version of the host driver (nvidia-smi). After an apt
  # update of the driver, set the new version and the hash that this prints:
  #   nix store prefetch-file https://download.nvidia.com/XFree86/Linux-x86_64/<version>/NVIDIA-Linux-x86_64-<version>.run
  targets.genericLinux.gpu = lib.mkIf isLinux {
    enable = true;
    # The NVIDIA driver is unfree: allow it, and only it. The host already runs
    # this driver from apt, under the same NVIDIA license.
    packages = import inputs.nixpkgs {
      inherit system;
      config = {
        allowUnfreePredicate = p: lib.getName p == "nvidia-x11";
        nvidia.acceptLicense = true;
      };
    };
    nvidia = {
      enable = true;
      version = "580.178.04";
      sha256 = "sha256-WXWobuRb/8tib1GuM9EWmxCBhqLqR61lHnLxP6S21vk=";
    };
  };

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
