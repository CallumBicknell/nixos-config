{ config, pkgs, ... }:

{
  # System-level hyprland helper: ensure packages and a Wayland session are present.
  environment.systemPackages = with pkgs; [
    hyprland
    hyprutils
    hyprshot
    hyprpicker
    hyprlock
    xdg-desktop-portal-hyprland
    waybar
  ];

  environment.etc."xdg/wayland-sessions/hyprland.desktop".text = ''
    [Desktop Entry]
    Name=Hyprland
    Exec=Hyprland
    Type=Application
  '';
}
