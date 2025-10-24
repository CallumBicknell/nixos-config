{ config, pkgs, ... }:

{
  # Installer-related helpers. This module doesn't change runtime behaviour by default;
  # it provides documentation and tools for using `disko` to create an encrypted Btrfs layout.

  environment.systemPackages = with pkgs; [ disko cryptsetup btrfs-progs ];

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
}
