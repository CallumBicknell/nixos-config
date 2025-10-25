{ config, pkgs, ... }:

{
  # Installer-related helpers. This module doesn't change runtime behaviour by default;
  # it provides documentation and tools for using `disko` to create an encrypted Btrfs layout.

  environment.systemPackages = with pkgs; [
    disko
    cryptsetup
    btrfs-progs
  ];

  # Example notes / placeholders for a LUKS + Btrfs setup. These are intentionally
  # commented out — uncomment and adjust device paths when you're installing.
  #
  # boot.initrd.luks.devices = {
  #   root = {
  #     device = "/dev/disk/by-partlabel/cryptroot"; # or /dev/nvme0n1p2
  #     preLVM = false;
  #     allowDiscards = false;
  #   };
  # };
  #
  # fileSystems = {
  #   "/" = {
  #     device = "/dev/mapper/root"; # after opening LUKS
  #     fsType = "btrfs";
  #     options = [ "subvol=@" "compress=zstd:1" "ssd" ];
  #   };
  #   "/home" = {
  #     device = "/dev/mapper/root";
  #     fsType = "btrfs";
  #     options = [ "subvol=@home" "compress=zstd:1" "ssd" ];
  #   };
  # };
  #
  # Example Snapper config (for btrfs snapshots). Configure and enable after install.
  # services.snapper = {
  #   enable = true;
  #   config."root" = {
  #     volumes = [ "/" ];
  #   };
  # };

  # Bootloader & installer recommendations
  #
  # This module provides conservative, opt-in defaults suitable for UEFI systems
  # and `--skip-disko` workflows. It does NOT force a bootloader install for all
  # environments — final bootloader configuration should come from the generated
  # `hardware-configuration.nix` on the target machine or from host-specific
  # overrides in `hosts/*.nix`.

  # Prefer systemd-boot on UEFI systems. These are set with mkDefault so host
  # hardware configs can override them when appropriate.
  boot.loader.systemd-boot.enable = pkgs.lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = pkgs.lib.mkDefault true;
  # Use a conventional mountpoint for the EFI System Partition on the installed
  # root. When using --skip-disko ensure you mount the ESP at /mnt/boot or
  # /mnt/boot/efi beforehand so the installer can install the bootloader.
  boot.loader.efi.efiSysMountPoint = pkgs.lib.mkDefault "/boot";

  # Secure Boot: supporting secure boot requires generating and enrolling keys
  # or using a shim. This is intentionally not enabled by default here because it
  # requires per-machine key management. If you want secure boot, enable and
  # configure it in your host-specific `hosts/*.nix` or the generated
  # `hardware-configuration.nix` after installation. Example flow:
  #  - generate an MOK/PK/KEK keypair
  #  - sign your EFI binaries
  #  - enroll keys in the firmware
  # See the NixOS manual on UEFI secure boot for detailed steps.

  # Partition labels: the disko plan already uses meaningful labels (ESP, luks,
  # etc.). If you prefer to mount partitions by label during `--skip-disko`, use
  # devices like "LABEL=ESP" in your `hosts/*.nix` or mount them manually under
  # /mnt before running this script.
}
