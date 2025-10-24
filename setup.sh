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
echo "  Target disk: ${TARGET_DISK:-<not set>}"
echo

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

echo
info "Disko completed successfully!"
info "Filesystems are mounted under /mnt"
echo

TARGET_REPO_PATH="/mnt/etc/nixos"
info "Copying configuration to $TARGET_REPO_PATH"
$SUDO mkdir -p "$TARGET_REPO_PATH"
# Don't overwrite machine-specific hardware config generated by nixos-generate-config
$SUDO rsync -a --exclude=.git --exclude=hardware-configuration.nix "$USE_DIR/" "$TARGET_REPO_PATH/"

# Generate hardware-configuration.nix for the target machine if possible.
# This is normally required for `nixos-install` to succeed on a new system.
if [ "$DRY_RUN" -eq 0 ]; then
    info "Generating /mnt/etc/nixos/hardware-configuration.nix"
    if command -v nixos-generate-config >/dev/null 2>&1; then
        ${SUDO} nixos-generate-config --root /mnt
    else
        info "nixos-generate-config not available; attempting via 'nix run'"
        ${SUDO} nix --experimental-features "nix-command flakes" run nixpkgs#nixos-generate-config -- --root /mnt
    fi
else
    info "Dry-run: skipping hardware configuration generation"
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
${SUDO} nixos-install --root /mnt --flake "$TARGET_REPO_PATH#$HOST"
INSTALL_STATUS=$?
set -e

if [ -n "$TMP_CLONE" ]; then
    info "Cleaning up temporary clone"
    rm -rf "$TMP_CLONE"
fi

echo
if [ $INSTALL_STATUS -ne 0 ]; then
    err "nixos-install failed with status $INSTALL_STATUS"
    echo "You may need to run it manually:"
    echo "  sudo nixos-install --root /mnt --flake $TARGET_REPO_PATH#$HOST"
    exit $INSTALL_STATUS
fi

info "Installation completed successfully!"
echo
echo "Next steps:"
echo "  1. Set root password if prompted"
echo "  2. Reboot: sudo reboot"
echo
echo "Done."
