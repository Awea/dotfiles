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
      # bun2nix defaults to nix-systems/default, which lists x86_64-darwin.
      # Nixpkgs 26.11 refuses to evaluate x86_64-darwin, so use ./systems.nix.
      inputs.bun2nix.inputs.systems.follows = "systems";
    };

    systems = {
      url = "path:./systems.nix";
      flake = false;
    };

    # Add extra flake inputs here, e.g.:
    # claude-tmux.url = "github:nielsgroen/claude-tmux";
  };

  outputs = { nixpkgs, home-manager, ... }@inputs:
    let
      mkHome = system: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        # Makes every flake input above available inside ./home.nix as `inputs`
        extraSpecialArgs = { inherit inputs; };

        modules = [ ./home.nix ];
      };
    in {
      # scripts/programs/nix-home-manager picks one from `uname`.
      homeConfigurations."awea" = mkHome "x86_64-linux";
      homeConfigurations."awea@mac" = mkHome "aarch64-darwin";
    };
}
