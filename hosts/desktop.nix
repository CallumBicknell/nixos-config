{ config, pkgs, ... }:

{
  networking.hostName = "desktop";

  # Import the desktop module to install Hyprland and related packages.
  imports = [ ./../modules/desktop.nix ./../modules/hyprland.nix ];

  # Enable autologin on tty1 for `callum` (use only if you want automatic console login).
  services.getty.autologinUser = "callum";
  systemd.services."getty@tty1".serviceConfig = {
    ExecStart = "${pkgs.util-linux}/bin/agetty --autologin callum --noclear %I $TERM";
  };
}
