{ pkgs, inputs, ... }:

{
  home.username = "awea";
  home.homeDirectory = "/home/awea";

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
  ];

  # To use a package from an extra flake input declared in flake.nix
  # (`system` is not a module arg, so reach it via pkgs.system):
  #   home.packages = with pkgs; [ ripgrep ]
  #     ++ [ inputs.claude-tmux.packages.${pkgs.system}.default ];
}
