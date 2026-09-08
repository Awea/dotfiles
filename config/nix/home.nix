{ pkgs, inputs, ... }:

let
  hunk = inputs.hunk.packages.${pkgs.system}.default;

  # Hunk's broker binds a single fixed loopback port (47657). A plain `daemon
  # serve` therefore crash-loops if a TUI already holds that port -- which can
  # happen when sd-switch restarts this service mid-`switch` while a `hunk diff`
  # window is open. Guard on the port itself: `hunk session list` is NOT a valid
  # liveness probe (it exits 0 even when no daemon is running), so test the bind
  # directly via bash's /dev/tcp. Only serve when the port is free.
  hunkDaemon = pkgs.writeShellScript "hunk-daemon-serve" ''
    if (exec 3<>/dev/tcp/127.0.0.1/47657) 2>/dev/null; then
      exec 3<&- 3>&-
      echo "hunk broker already listening on 47657; nothing to do"
      exit 0
    fi
    exec ${hunk}/bin/hunk daemon serve
  '';
in
{
  home.username = "awea";
  home.homeDirectory = "/home/awea";

  # Do NOT change after the first install.
  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.stateVersion
  home.stateVersion = "25.11";

  # Let home-manager manage itself.
  programs.home-manager.enable = true;

  # Start/restart changed systemd user services automatically on `switch`.
  systemd.user.startServices = "sd-switch";

  # Packages installed here land on $PATH everywhere (via ~/.nix-profile/bin).
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    uv
  ] ++ [
    hunk
  ];

  # Run the Hunk session daemon as a user service so it starts on login.
  systemd.user.services.hunk-daemon = {
    Unit = {
      Description = "Hunk session daemon and websocket broker";
      After = [ "default.target" ];
    };
    Service = {
      ExecStart = "${hunkDaemon}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
