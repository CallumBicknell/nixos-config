{
  description = "Callum's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      disko,
      ...
    }:
    let
      system = "x86_64-linux";

      makeConfig =
        host:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            disko.nixosModules.disko

            ./configuration.nix
            ./scripts/disko-desktop.nix
            ./hosts/${host}.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.callum = import ./home.nix { inherit pkgs; };
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        desktop = makeConfig "desktop";
        laptop = makeConfig "laptop";
      };
    };
}
