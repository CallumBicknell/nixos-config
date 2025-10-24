{ config, pkgs, ... }:

let
  hw =
    if builtins.pathExists ./hardware-configuration.nix then [ ./hardware-configuration.nix ] else [ ];
in

{
  # Import hardware config and modular pieces from ./modules
  imports = hw ++ [
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/services.nix
    ./modules/installer.nix
  ];

  # Basic machine identity
  time.timeZone = "Europe/London";

  # Enable Nix experimental features system-wide (makes `nix` commands like flakes available)
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Keep a pinned state version for compatibility
  system.stateVersion = "25.05";

  # Do not enable GRUB by default during local evaluation/installer runs.
  # Installing a boot loader requires knowing whether the target system is
  # BIOS or UEFI and which device/ESP to use. Leave this to the generated
  # `hardware-configuration.nix` on the target machine or to host-specific
  # overrides in `hosts/*.nix`.
  boot.loader.grub.enable = pkgs.lib.mkDefault false;
}
