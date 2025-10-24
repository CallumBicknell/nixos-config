{ config, pkgs, ... }:

let
  hw = if builtins.pathExists ./hardware-configuration.nix then [ ./hardware-configuration.nix ] else [];
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

  # Provide a safe default for the GRUB installation target so `nixos-install`
  # won't fail when `hardware-configuration.nix` is not present. Users should
  # override this in their generated hardware config or host-specific files.
  boot.loader.grub = {
    enable = true;
    # Default to /dev/sda in evaluation-only contexts; this can be overridden.
    devices = pkgs.lib.mkDefault [ "/dev/sda" ];
  };
}
