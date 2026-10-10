{
  description = "awea home-manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hunk = {
      url = "github:VoidLattice/hunk/feat/reviewed-hunks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add extra flake inputs here, e.g.:
    # claude-tmux.url = "github:nielsgroen/claude-tmux";
  };

  outputs = { nixpkgs, home-manager, ... }@inputs:
    let
      # One home-manager configuration per platform, built from the same
      # ./home.nix. Flakes are pure (no builtins.currentSystem), so each
      # platform gets its own output: scripts/programs/nix-home-manager picks
      # one from `uname`.
      mkHome = system: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        # Makes every flake input above available inside ./home.nix as `inputs`
        extraSpecialArgs = { inherit inputs; };

        modules = [ ./home.nix ];
      };
    in {
      homeConfigurations."awea" = mkHome "x86_64-linux";
      homeConfigurations."awea@mac" = mkHome "aarch64-darwin";
    };
}
