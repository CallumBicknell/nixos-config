{ config, pkgs, ... }:

{
  # Common packages (pulled from your current system snapshot). Add/remove as you like.
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    zsh

    # Hyprland / Wayland ecosystem
    hyprland
    wayland
    wayland-protocols
    wlroots
    xdg-desktop-portal-hyprland
    waybar
    wl-clipboard
    wl-clip-persist
    slurp
    grim

    # Audio
    pipewire
    wireplumber

    # Utilities
    fzf
    ripgrep
    starship
    kitty
    tmux
    htop

    # Development
    nodejs
    npm
    rustc
    rust-analyzer
    go

    # Installer / disks
    disko
    cryptsetup
    btrfs-progs
    snapper
  ];
}
