{ config, pkgs, ... }:

{
  # Enable common services. Add or extend here.
  services.openssh.enable = true;

  # NetworkManager is useful if you used it on Arch
  networking.networkmanager.enable = true;
}
