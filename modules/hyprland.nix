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

  wayland.windowManager.hyprland.settings = {
    "$mod" = "SUPER";
    bind = [
      "$mod, F, exec, firefox"
      ", Print, exec, grim -g "$SELECTION" - | satty --filename - --output-filename "$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" --early-exit --actions-on-enter save-to-clipboard --save-after-copy --copy-command 'wl-copy'"
    ]
    ++ (
      # workspaces
      # binds $mod + [shift +] {1..9} to [move to] workspace {1..9}
      builtins.concatLists (
        builtins.genList (
          i:
          let
            ws = i + 1;
          in
          [
            "$mod, code:1${toString i}, workspace, ${toString ws}"
            "$mod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
          ]
        ) 9
      )
    );
  };

}
