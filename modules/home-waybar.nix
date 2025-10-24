{ pkgs, ... }:

{
  # Waybar: install package and make a couple of sane environment settings.
  home = {
    packages = with pkgs; [ waybar waybar-hyprland ];

    # Export an XDG variable so modules that consume it can find Waybar config
    sessionVariables = {
      WAYBAR_CONFIG = "$HOME/.config/waybar/config";
    };
  };
}
