{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    hyprland
    wayland
    wayland-protocols
    wlroots
    xdg-desktop-portal-hyprland
    waybar
    wl-clipboard
    slurp
    grim
    pipewire
    wireplumber
  ];

  # Register Hyprland as a Wayland session so DMs can see it. Use /usr/share which is common.
  environment.etc."usr/share/wayland-sessions/hyprland.desktop".text = ''
[Desktop Entry]
Name=Hyprland
Exec=Hyprland
Type=Application
'';
}