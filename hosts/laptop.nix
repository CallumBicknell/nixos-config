{ config, pkgs, ... }:

{
  networking.hostName = "laptop";

  # Laptop uses the same desktop module for reproducibility.
  imports = [ ./../modules/desktop.nix ./../modules/hyprland.nix ];

  # Enable autologin on tty1 for `callum` (use only if you want automatic console login).
  services.getty.autologinUser = "callum";
  systemd.services."getty@tty1".serviceConfig = {
    ExecStart = "${pkgs.util-linux}/bin/agetty --autologin callum --noclear %I $TERM";
  };
}
