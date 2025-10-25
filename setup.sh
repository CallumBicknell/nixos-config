#!/usr/bin/env bash
set -euo pipefail

# Configuration
readonly REPO_URL="https://github.com/CallumBicknell/nixos-config.git"
readonly TEMP_DIR="/tmp/nixos-config"
readonly SECRET_KEY_PATH="/tmp/secret.key"
readonly INSTALL_PATH="/mnt/etc/nixos"

# Cleanup function to remove sensitive files
cleanup() {
    if [[ -f "$SECRET_KEY_PATH" ]]; then
        log_info "Removing secret key file..."
        shred -u "$SECRET_KEY_PATH" 2>/dev/null || rm -f "$SECRET_KEY_PATH"
    fi
}

trap cleanup EXIT

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    local deps=("git" "nixos-install")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required command '$dep' not found"
            exit 1
        fi
    done
}

clone_repository() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_warn "Temporary directory already exists, removing..."
        rm -rf "$TEMP_DIR"
    fi
    
    log_info "Cloning repository to $TEMP_DIR..."
    git clone "$REPO_URL" "$TEMP_DIR"
}

select_disk() {
    log_info "Available disks:"
    lsblk -d -n -p -o NAME,SIZE,TYPE | grep disk
    echo
    
    read -rp "Enter the disk to install to (e.g., /dev/nvme0n1): " selected_disk
    
    if [[ ! -b "$selected_disk" ]]; then
        log_error "Invalid disk: $selected_disk"
        exit 1
    fi
    
    log_warn "WARNING: All data on $selected_disk will be destroyed!"
    read -rp "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    echo "$selected_disk"
}

get_encryption_passphrase() {
    log_info "Setting up disk encryption..."
    
    while true; do
        read -rsp "Enter encryption passphrase: " passphrase
        echo
        read -rsp "Confirm encryption passphrase: " passphrase_confirm
        echo
        
        if [[ "$passphrase" == "$passphrase_confirm" ]]; then
            echo -n "$passphrase" > "$SECRET_KEY_PATH"
            chmod 600 "$SECRET_KEY_PATH"
            log_info "Passphrase saved to $SECRET_KEY_PATH"
            break
        else
            log_error "Passphrases do not match. Please try again."
        fi
    done
}

replace_disk_references() {
    local disk=$1
    log_info "Replacing disk references with $disk..."
    
    find "$TEMP_DIR" -type f \( -name "*.nix" -o -name "*.sh" \) -exec \
        sed -i "s|/dev/nvme0n1|$disk|g" {} +
}

run_disko() {
    log_info "Running disko to partition and format disks..."
    
    local disko_config="$TEMP_DIR/scripts/disko-desktop.nix"
    if [[ ! -f "$disko_config" ]]; then
        log_error "Disko configuration not found: $disko_config"
        exit 1
    fi
    
    if ! nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
        --mode disko "$disko_config"; then
        log_error "Disko failed to partition and format disks"
        exit 1
    fi
}

generate_hardware_config() {
    log_info "Generating hardware configuration..."
    
    # Use --no-filesystems since disko already created the filesystem layout
    if ! nixos-generate-config --no-filesystems --root /mnt; then
        log_error "Failed to generate hardware configuration"
        exit 1
    fi
    
    log_info "Hardware configuration generated at /mnt/etc/nixos/hardware-configuration.nix"
}

copy_configuration() {
    log_info "Copying configuration to $INSTALL_PATH..."
    
    mkdir -p "$INSTALL_PATH"
    cp -r "$TEMP_DIR"/* "$INSTALL_PATH/"
    
    # Preserve the disko configuration in the installed system
    local disko_config="$TEMP_DIR/scripts/disko-desktop.nix"
    if [[ -f "$disko_config" ]]; then
        log_info "Preserving disko configuration..."
        cp "$disko_config" "$INSTALL_PATH/disko-config.nix"
    fi
}

select_host() {
    local hosts_dir="$INSTALL_PATH/hosts"
    
    if [[ ! -d "$hosts_dir" ]]; then
        log_error "Hosts directory not found: $hosts_dir"
        exit 1
    fi
    
    log_info "Available hosts:"
    local -a hosts
    local i=1
    
    for host_file in "$hosts_dir"/*.nix; do
        local host_name=$(basename "$host_file" .nix)
        hosts+=("$host_name")
        echo "  $i) $host_name"
        ((i++))
    done
    
    echo
    read -rp "Select host to install (1-${#hosts[@]}): " host_selection
    
    if [[ ! "$host_selection" =~ ^[0-9]+$ ]] || \
       [[ "$host_selection" -lt 1 ]] || \
       [[ "$host_selection" -gt "${#hosts[@]}" ]]; then
        log_error "Invalid selection"
        exit 1
    fi
    
    echo "${hosts[$((host_selection-1))]}"
}

check_esp_mounted() {
    log_info "Checking for EFI System Partition..."
    
    if [[ -d /sys/firmware/efi ]]; then
        # System is UEFI, check if ESP is mounted
        if ! mountpoint -q /mnt/boot/efi && ! mountpoint -q /mnt/boot; then
            log_warn "ESP does not appear to be mounted at /mnt/boot or /mnt/boot/efi"
            log_warn "systemd-boot installation may fail"
            read -rp "Continue anyway? (yes/no): " continue_anyway
            if [[ "$continue_anyway" != "yes" ]]; then
                log_info "Installation cancelled"
                exit 0
            fi
        else
            log_info "ESP is mounted correctly"
        fi
    else
        log_info "System appears to be BIOS mode (non-UEFI)"
    fi
}

install_nixos() {
    local host=$1
    log_info "Installing NixOS with host configuration: $host"
    
    cd "$INSTALL_PATH" || {
        log_error "Failed to change to $INSTALL_PATH"
        exit 1
    }
    
    if ! nixos-install --flake ".#$host"; then
        log_error "NixOS installation failed. Check the output above for details."
        log_info "You can try entering a chroot to fix issues manually"
        exit 1
    fi
}

post_install_action() {
    log_info "Installation complete!"
    echo
    echo "What would you like to do next?"
    echo "  1) Reboot into the new system"
    echo "  2) Chroot into the new system"
    echo "  3) Exit"
    echo
    
    read -rp "Select option (1-3): " action
    
    case "$action" in
        1)
            log_info "Rebooting..."
            reboot
            ;;
        2)
            log_info "Entering chroot environment..."
            nixos-enter
            ;;
        3)
            log_info "Exiting. Don't forget to reboot!"
            ;;
        *)
            log_warn "Invalid option. Exiting."
            ;;
    esac
}

main() {
    log_info "Starting NixOS setup..."
    
    check_root
    check_dependencies
    clone_repository
    
    local disk
    disk=$(select_disk)
    
    get_encryption_passphrase
    replace_disk_references "$disk"
    run_disko
    generate_hardware_config
    copy_configuration
    
    local host
    host=$(select_host)
    
    check_esp_mounted
    install_nixos "$host"
    post_install_action
}

main "$@"