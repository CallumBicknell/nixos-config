{ pkgs, ... }:

{
  # Hyprland user-level pieces: install hyprland-related helper tools and set env vars.
  home = {
    packages = with pkgs; [
      hyprland
      hyprland-qt-support
      hyprland-qtutils
      xdg-desktop-portal-hyprland
    ];

    # Set a session variable to point at a default Hyprland config dir
    sessionVariables = {
      HYPRLAND_CONFIG = "$HOME/.config/hyprland";
    };
  };
}
