{
  description = "Callum's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
  let
    system = "x86_64-linux";
    makeConfig = host: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./configuration.nix
        ./hosts/${host}.nix

        home-manager.nixosModules.home-manager
        ({ config, pkgs, ... }: {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.callum = import ./home.nix;
        })
      ];
    };
  in {
    nixosConfigurations = {
      desktop = makeConfig "desktop";
      laptop = makeConfig "laptop";
    };
  };
}
