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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."awea" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Makes every flake input above available inside ./home.nix as `inputs`
        extraSpecialArgs = { inherit inputs; };

        modules = [ ./home.nix ];
      };
    };
}
