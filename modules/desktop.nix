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

  # Ensure the system console and desktop use the UK / GB keyboard layout.
  # - console.keyMap sets the kernel console layout (tty)
  # - environment.sessionVariables exports XKB variables for graphical sessions
  #   (Wayland compositors and some display managers read these).
  console.keyMap = "uk";

  environment.sessionVariables = {
    XKB_DEFAULT_LAYOUT = "gb";
    XKB_DEFAULT_VARIANT = "";
  };
}
