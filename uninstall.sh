#!/bin/bash

# BunProxy Uninstallation Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/bunproxy"
USER="bunproxy"

# Functions
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}Success: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}Info: $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

confirm_uninstall() {
    echo -e "${RED}WARNING: This will completely remove BunProxy from your system!${NC}"
    echo "This includes:"
    echo "  - BunProxy service and files"
    echo "  - Configuration files in $CONFIG_DIR"
    echo "  - SSL certificates in $CONFIG_DIR/ssl"
    echo "  - System user $USER"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY == "yes" ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
}

stop_service() {
    print_info "Stopping BunProxy service..."
    
    if systemctl is-active --quiet bunproxy; then
        systemctl stop bunproxy
        print_success "Service stopped"
    else
        print_info "Service is not running"
    fi
    
    if systemctl is-enabled --quiet bunproxy 2>/dev/null; then
        systemctl disable bunproxy
        print_success "Service disabled"
    fi
}

remove_files() {
    print_info "Removing BunProxy files..."
    
    # Remove systemd service
    rm -f /etc/systemd/system/bunproxy.service
    systemctl daemon-reload
    
    # Remove binary
    rm -f "$INSTALL_DIR/bunproxy"
    
    print_success "Files removed"
}

remove_config() {
    print_info "Removing configuration files..."
    
    # Backup config before removal
    if [[ -f "$CONFIG_DIR/config.json" ]]; then
        cp "$CONFIG_DIR/config.json" "/tmp/bunproxy-config-backup-$(date +%Y%m%d-%H%M%S).json"
        print_info "Configuration backed up to /tmp/"
    fi
    
    # Remove config directory
    rm -rf "$CONFIG_DIR"
    
    print_success "Configuration removed"
}

remove_user() {
    print_info "Removing system user..."
    
    if id "$USER" &>/dev/null; then
        userdel "$USER"
        print_success "User $USER removed"
    else
        print_info "User $USER does not exist"
    fi
}

remove_acme_renewal() {
    print_info "Checking for acme.sh certificate renewal entries..."
    
    if [[ -d "/root/.acme.sh" ]]; then
        # List all domains managed by acme.sh
        DOMAINS=$(/root/.acme.sh/acme.sh --list 2>/dev/null | grep -E "^\s*[0-9]+" | awk '{print $2}' || true)
        
        if [[ ! -z "$DOMAINS" ]]; then
            echo "Found the following domains in acme.sh:"
            echo "$DOMAINS"
            echo
            read -p "Do you want to remove BunProxy-related certificates? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -p "Enter the domain to remove (or press Enter to skip): " DOMAIN
                if [[ ! -z "$DOMAIN" ]]; then
                    /root/.acme.sh/acme.sh --remove -d "$DOMAIN"
                    print_success "Certificate entry removed"
                fi
            fi
        fi
    fi
}

print_summary() {
    echo
    echo "=========================================="
    print_success "BunProxy uninstallation completed!"
    echo "=========================================="
    echo
    echo "Removed:"
    echo "  ✓ BunProxy service"
    echo "  ✓ Binary file"
    echo "  ✓ Configuration directory"
    echo "  ✓ System user"
    echo
    echo "Note: Configuration was backed up to /tmp/"
    echo
}

# Main uninstallation flow
main() {
    print_info "BunProxy Uninstaller"
    echo
    
    check_root
    confirm_uninstall
    stop_service
    remove_files
    remove_config
    remove_user
    remove_acme_renewal
    print_summary
}

# Run main function
main "$@" 