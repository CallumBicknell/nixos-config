#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

# If running as root, don't use sudo; otherwise prefix destructive commands with sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "== NixOS Disk/Install Helper"

confirm() {
    read -rp "$1 [y/N]: " ans
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

info() { 
    printf "== %s\n" "$1"
}

err() { 
    printf "ERROR: %s\n" "$1" >&2
}

# cleanup temporary files and clones on exit
cleanup() {
    [ -n "${TMP_NIX:-}" ] && [ -f "$TMP_NIX" ] && rm -f "$TMP_NIX" || true
    [ -n "${TMP_CLONE:-}" ] && [ -d "$TMP_CLONE" ] && rm -rf "$TMP_CLONE" || true
}

trap cleanup EXIT

# Enter a chroot under /mnt to allow manual repairs. This binds /dev, /proc,
# /sys, /run and /dev/pts into the target and launches an interactive shell.
enter_chroot() {
    info "Preparing chroot environment under /mnt"
    # bind mount required filesystems
    $SUDO mount --bind /dev /mnt/dev || true
    $SUDO mount --bind /dev/pts /mnt/dev/pts || true
    $SUDO mount -t proc proc /mnt/proc || true
    $SUDO mount -t sysfs sys /mnt/sys || true
    $SUDO mount --bind /run /mnt/run || true

    info "Entering chroot (/mnt). Exit the shell to continue the installer."
    # Prefer an interactive bash if available
    if $SUDO test -x /mnt/bin/bash >/dev/null 2>&1; then
        $SUDO chroot /mnt /bin/bash --login
    else
        $SUDO chroot /mnt /bin/sh
    fi

    info "Left chroot; cleaning up mounts"
    # Attempt to unmount in reverse order; tolerate failures
    $SUDO umount -l /mnt/run || true
    $SUDO umount -l /mnt/sys || true
    $SUDO umount -l /mnt/proc || true
    $SUDO umount -l /mnt/dev/pts || true
    $SUDO umount -l /mnt/dev || true
}

# Detect an EFI System Partition (ESP) on the target disk(s) and mount it under
# /mnt/boot/efi (or /mnt/boot) so UEFI bootloaders (systemd-boot, GRUB EFI)
# can be installed when using --skip-disko. This is conservative and will only
# attempt to mount a partition if it can find a likely ESP.
mount_esp_if_needed() {
    # Only run when /mnt exists
    if ! mountpoint -q /mnt; then
        return 0
    fi

    # prefer /mnt/boot/efi, fallback to /mnt/boot
    local esp_mount="/mnt/boot/efi"
    local alt_mount="/mnt/boot"

    # if already mounted, nothing to do
    if mountpoint -q "$esp_mount" || mountpoint -q "$alt_mount"; then
        info "ESP already mounted under $esp_mount or $alt_mount"
        return 0
    fi

    info "Looking for an EFI System Partition (ESP) to mount under $esp_mount"

    # Look for partitions with fstype vfat, or PARTLABEL/LABEL containing EFI or ESP,
    # or the EFI partition GUID. Use lsblk to inspect block devices.
    local candidate
    # prefer explicit PARTLABEL or LABEL matches
    candidate=$(lsblk -pn -o NAME,PARTLABEL,LABEL,FSTYPE,PARTTYPE | awk '$3 ~ /EFI|ESP/ || $4=="vfat" { print $1 }' | head -n1 || true)
    if [ -z "$candidate" ]; then
        # fallback to checking PARTTYPE GUID for EFI: c12a7328-f81f-11d2-ba4b-00a0c93ec93b
        candidate=$(lsblk -pn -o NAME,PARTTYPE | awk 'tolower($2) ~ /c12a7328-f81f-11d2-ba4b-00a0c93ec93b/ { print $1 }' | head -n1 || true)
    fi
    if [ -z "$candidate" ]; then
        info "No obvious ESP found (no vfat/EFI partition). Skipping automatic mount."
        return 0
    fi

    info "Found candidate ESP: $candidate"

    # Create mountpoint and attempt mount
    $SUDO mkdir -p "$esp_mount"
    if $SUDO mount -t vfat "$candidate" "$esp_mount" 2>/dev/null; then
        info "Mounted $candidate -> $esp_mount"
        return 0
    fi

    # try mounting to /mnt/boot if /mnt/boot/efi fails
    $SUDO mkdir -p "$alt_mount"
    if $SUDO mount -t vfat "$candidate" "$alt_mount" 2>/dev/null; then
        info "Mounted $candidate -> $alt_mount"
        return 0
    fi

    info "Failed to mount $candidate as vfat under $esp_mount or $alt_mount"
    return 0
}

usage() {
    cat <<EOF
Usage: $0 [options]

This script applies the disko disk plan and installs NixOS.

Options:
  -d, --device DEVICE     Target block device (e.g. /dev/nvme0n1) [required]
  -r, --repo URL          Git URL of your nixos-config (required if not in repo)
  -h, --host HOST         Host name in flake (desktop|laptop). Default: desktop
  -y, --yes               Skip confirmation prompts (dangerous!)
    --dry-run               Don't run destructive commands; validate plan and exit
  --help                  Show this help

Examples:
  # From within the cloned repo:
  ./setup.sh -d /dev/nvme0n1 -h desktop

  # Via curl (from remote):
  curl -sSL <raw-url> | bash -s -- -d /dev/nvme0n1 -r https://github.com/user/nixos-config.git

EOF
}

HOST="desktop"
REPO_URL=""
YES=0
TARGET_DISK=""
DRY_RUN=0
SKIP_DISKO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device) 
            TARGET_DISK="$2"
            shift 2
            ;;
        -r|--repo) 
            REPO_URL="$2"
            shift 2
            ;;
        -h|--host) 
            HOST="$2"
            shift 2
            ;;
        -y|--yes) 
            YES=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-disko)
            SKIP_DISKO=1
            shift
            ;;
        --help) 
            usage
            exit 0
            ;;
        *) 
            err "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# If dry-run, auto-confirm prompts to avoid interactive destructive confirmations
if [ "$DRY_RUN" -eq 1 ]; then
    YES=1
fi

echo
info "Configuration:"
echo "  Host: $HOST"
if [ "$SKIP_DISKO" -eq 1 ]; then
    echo "  Target disk: <skip-disko enabled>"
else
    echo "  Target disk: ${TARGET_DISK:-<not set>}"
fi
echo

# When skipping disko we must not prompt for or validate the block device.
if [ "$SKIP_DISKO" -eq 1 ]; then
    info "--skip-disko set: assuming target device has been prepared and mounted under /mnt"
    # require /mnt to be a mount point and don't ask for a block device
    if ! mountpoint -q /mnt; then
        err "/mnt is not a mount point. When using --skip-disko you must mount target filesystems under /mnt before running the script."
        exit 1
    fi
else
    if [ -z "$TARGET_DISK" ]; then
        echo "Available block devices:"
        lsblk -dpn -o NAME,SIZE,MODEL || true
        echo
        read -rp "Enter the block device to use (e.g. /dev/nvme0n1): " TARGET_DISK
    fi

    if [ -z "$TARGET_DISK" ]; then
        err "No device specified. Aborting."
        exit 1
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        if [ ! -b "$TARGET_DISK" ]; then
            err "Device $TARGET_DISK does not exist or is not a block device."
            exit 1
        fi
    else
        info "Dry-run: skipping block device existence check for $TARGET_DISK"
    fi

    echo
    info "WARNING: This will DESTROY ALL DATA on $TARGET_DISK"
    if [ "$YES" -eq 0 ]; then
        if ! confirm "Proceed with formatting $TARGET_DISK?"; then
            echo "Aborting."
            exit 1
        fi
    fi
fi

USE_DIR="$ROOT_DIR"
TMP_CLONE=""

if [ -f "$ROOT_DIR/flake.nix" ]; then
    info "Using config from current directory: $ROOT_DIR"
else
    if [ -z "$REPO_URL" ]; then
        err "No flake.nix found in current directory and no --repo provided."
        echo "When running via curl, you must provide --repo <git-url>"
        exit 1
    fi
    
    TMP_CLONE=$(mktemp -d /tmp/nixos-config-clone.XXXX)
    info "Cloning $REPO_URL -> $TMP_CLONE"
    git clone --depth 1 "$REPO_URL" "$TMP_CLONE"
    USE_DIR="$TMP_CLONE"
fi

if [ "$SKIP_DISKO" -eq 0 ]; then
    DISKO_PLAN="$USE_DIR/scripts/disko-desktop.nix"
    if [ ! -f "$DISKO_PLAN" ]; then
        err "Disko plan not found: $DISKO_PLAN"
        [ -n "$TMP_CLONE" ] && rm -rf "$TMP_CLONE"
        exit 1
    fi

    TMP_NIX=$(mktemp /tmp/disko-plan.XXXX.nix)
    cat > "$TMP_NIX" <<NIX
let
    plan = import "$DISKO_PLAN" { device = "$TARGET_DISK"; };
in
  plan
NIX

    info "Created temporary disko plan: $TMP_NIX"
    echo

    info "Running disko (this will destroy data on $TARGET_DISK)"
    echo "You may be prompted for your sudo password..."
    echo

    if [ "$DRY_RUN" -eq 1 ]; then
        info "Dry-run mode: will not execute disko or nixos-install."
        echo
        info "Temporary disko plan ($TMP_NIX) contents:"
        echo "----"
        # print_plan: prefer sed, fall back to head or cat so minimal container images work
        if command -v sed >/dev/null 2>&1; then
            sed -n '1,200p' "$TMP_NIX" || true
        elif command -v head >/dev/null 2>&1; then
            head -n 200 "$TMP_NIX" || true
        else
            cat "$TMP_NIX" || true
        fi
        echo "----"
        info "Plan generation validated. Exiting due to --dry-run."
        rm -f "$TMP_NIX"
        [ -n "$TMP_CLONE" ] && rm -rf "$TMP_CLONE"
        exit 0
    fi

    if ! $SUDO nix --experimental-features "nix-command flakes" run \
        github:nix-community/disko/latest -- \
        --mode destroy,format,mount "$TMP_NIX"; then
        err "Disko failed!"
        rm -f "$TMP_NIX"
        [ -n "$TMP_CLONE" ] && rm -rf "$TMP_CLONE"
        exit 1
    fi

    rm -f "$TMP_NIX"
else
    info "--skip-disko: not running disko; assuming device already formatted and mounted under /mnt"
fi

echo
info "Disko completed successfully!"
info "Filesystems are mounted under /mnt"
echo

# If skipping disko, try to detect and mount an ESP so UEFI bootloader installs succeed.
if [ "$SKIP_DISKO" -eq 1 ]; then
    mount_esp_if_needed
fi

TARGET_REPO_PATH="/mnt/etc/nixos"
info "Copying configuration to $TARGET_REPO_PATH"
$SUDO mkdir -p "$TARGET_REPO_PATH"
# Don't overwrite machine-specific hardware config generated by nixos-generate-config
$SUDO rsync -a --exclude=.git --exclude=hardware-configuration.nix "$USE_DIR/" "$TARGET_REPO_PATH/"

# Generate hardware-configuration.nix for the target machine if possible.
# This is normally required for `nixos-install` to succeed on a new system.
if [ "$DRY_RUN" -eq 0 ]; then
    info "Generating /mnt/etc/nixos/hardware-configuration.nix"
    # When USING disko to create partitions we generally want to keep the
    # filesystem layout produced by disko and avoid having
    # `nixos-generate-config` regenerate `fileSystems` entries that may
    # conflict. In that case use --no-filesystems. If the user skipped disko
    # (pre-mounted filesystems manually) allow generating the full config.
    if command -v nixos-generate-config >/dev/null 2>&1; then
        if [ "$SKIP_DISKO" -eq 0 ]; then
            ${SUDO} nixos-generate-config --no-filesystems --root /mnt
        else
            ${SUDO} nixos-generate-config --root /mnt
        fi
    else
        info "nixos-generate-config not available; attempting via 'nix run'"
        if [ "$SKIP_DISKO" -eq 0 ]; then
            ${SUDO} nix --experimental-features "nix-command flakes" run nixpkgs#nixos-generate-config -- --no-filesystems --root /mnt
        else
            ${SUDO} nix --experimental-features "nix-command flakes" run nixpkgs#nixos-generate-config -- --root /mnt
        fi
    fi
else
    info "Dry-run: skipping hardware configuration generation"
fi

# If we used the current repository (not a temporary clone), copy the
# generated hardware-configuration.nix back into the working repo so the
# flake evaluated for installation includes the real hardware config. When
# using a temporary clone (running from remote --repo), do not modify the
# clone; instead the installer will use the files under /mnt/etc/nixos.
if [ -z "$TMP_CLONE" ]; then
    if [ -f /mnt/etc/nixos/hardware-configuration.nix ]; then
        info "Copying generated hardware-configuration.nix -> $USE_DIR/hardware-configuration.nix"
        # Use sudo cat to preserve permissions when running as non-root
        if [ "${SUDO:-}" = "" ]; then
            cp /mnt/etc/nixos/hardware-configuration.nix "$USE_DIR/hardware-configuration.nix"
        else
            $SUDO cp /mnt/etc/nixos/hardware-configuration.nix "$USE_DIR/hardware-configuration.nix"
            $SUDO chown $(id -u):$(id -g) "$USE_DIR/hardware-configuration.nix" || true
        fi
    else
        info "No generated hardware-configuration.nix found under /mnt/etc/nixos"
    fi
else
    info "Temporary clone in use; not copying generated hardware-configuration.nix back to clone"
fi

echo
info "Running nixos-install for host '$HOST'"
if [ "$YES" -eq 0 ]; then
    if ! confirm "Proceed with nixos-install?"; then
        err "Aborting before installation."
        [ -n "$TMP_CLONE" ] && rm -rf "$TMP_CLONE"
        exit 1
    fi
fi

echo
set +e
FLAKE_PATH="$TARGET_REPO_PATH"
# If we copied the generated hardware config back into the local repo, prefer
# using the working directory flake so it includes that file during evaluation.
if [ -z "$TMP_CLONE" ] && [ -f "$USE_DIR/hardware-configuration.nix" ]; then
    FLAKE_PATH="$USE_DIR"
    info "Using local flake path with generated hardware config: $FLAKE_PATH"
fi
${SUDO} nixos-install --root /mnt --flake "$FLAKE_PATH#$HOST"
INSTALL_STATUS=$?
set -e

if [ -n "$TMP_CLONE" ]; then
    info "Cleaning up temporary clone"
    rm -rf "$TMP_CLONE"
fi

echo
if [ $INSTALL_STATUS -ne 0 ]; then
    err "nixos-install failed with status $INSTALL_STATUS"

    # Offer to enter a chroot so the user can make manual fixes.
    if confirm "Enter a chroot at /mnt to make fixes and then retry installation?"; then
        enter_chroot

        # After leaving chroot, offer to retry nixos-install once more.
        if confirm "Retry nixos-install now?"; then
            set +e
            ${SUDO} nixos-install --root /mnt --flake "$FLAKE_PATH#$HOST"
            INSTALL_STATUS=$?
            set -e
        fi
    fi

    if [ $INSTALL_STATUS -ne 0 ]; then
        echo "You may need to run it manually:"
        echo "  sudo nixos-install --root /mnt --flake $FLAKE_PATH#$HOST"
        exit $INSTALL_STATUS
    fi
fi

info "Installation completed successfully!"
echo
echo "Next steps:"
echo "  1. Set root password if prompted"
echo "  2. Reboot: sudo reboot"
echo
echo "Done."
