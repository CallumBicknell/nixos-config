{ pkgs, ... }:

let
  lib = pkgs.lib;
  hypr = import ./modules/home-hyprland.nix { inherit pkgs; };
  waybar = import ./modules/home-waybar.nix { inherit pkgs; };
  neovim = import ./modules/home-neovim.nix { inherit pkgs; };
  base = {
    home = {
      username = "callum";
      homeDirectory = "/home/callum";
    };

    programs = { zsh = { enable = true; }; };

    home.packages = with pkgs; [ git zsh starship neovim ];
  };
in
lib.mkMerge [ base hypr waybar neovim ]
