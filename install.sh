#!/bin/bash

# BunProxy Installation Script
# This script installs BunProxy HTTP/2 forward proxy server from a pre-compiled binary.
# Built with Bun runtime for superior performance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/bunproxy"
SSL_DIR="$CONFIG_DIR/ssl"
USER="bunproxy"
GROUP="bunproxy"

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

check_dependencies() {
    print_info "Checking dependencies..."
    
    if ! command -v systemctl &> /dev/null; then
        print_error "systemctl is not available. This script requires a systemd-based Linux distribution."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed. Please install it first (e.g., sudo apt install curl)."
        exit 1
    fi
    
    print_success "All dependencies are satisfied"
}

install_acme() {
    print_info "Installing acme.sh for automatic SSL certificate management..."
    
    if [[ ! -d "/root/.acme.sh" ]]; then
        curl https://get.acme.sh | sh -s email=$1
        print_success "acme.sh installed successfully"
    else
        print_info "acme.sh is already installed"
    fi
}

create_user() {
    print_info "Creating system user for BunProxy..."
    
    if ! id "$USER" &>/dev/null; then
        useradd --system --no-create-home --shell /bin/false "$USER"
        print_success "User $USER created"
    else
        print_info "User $USER already exists"
    fi
}

create_directories() {
    print_info "Creating necessary directories..."
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$SSL_DIR"
    
    # Set permissions
    chown -R "$USER:$GROUP" "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 700 "$SSL_DIR"
    
    print_success "Directories created"
}

install_files() {
    print_info "Installing BunProxy binary..."

    local BINARY_NAME="nodeproxy"

    if [[ ! -f "$BINARY_NAME" ]]; then
        print_error "Binary '$BINARY_NAME' not found."
        print_error "Please make sure the binary is in the same directory as the install script."
        exit 1
    fi

    # Copy binary
    cp "$BINARY_NAME" "$INSTALL_DIR/bunproxy"
    chmod +x "$INSTALL_DIR/bunproxy"
    
    # Update and install systemd service
    if [[ ! -f "nodeproxy.service" ]]; then
        print_error "Service file not found."
        exit 1
    fi
    
    # Modify service file to use bunproxy
    cat nodeproxy.service | sed 's/nodeproxy/bunproxy/g' > bunproxy.service
    cp bunproxy.service /etc/systemd/system/
    rm -f bunproxy.service
    
    print_success "Files installed"
}

configure_proxy() {
    print_info "Configuring BunProxy..."
    
    # Check if config.json.example exists and use it to propose defaults
    local DEFAULT_DOMAIN="proxy.example.com"
    local DEFAULT_EMAIL="admin@example.com"
    
    # Interactive configuration
    echo
    read -p "Enter proxy domain (e.g., $DEFAULT_DOMAIN): " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
    read -p "Enter email for SSL certificate (e.g., $DEFAULT_EMAIL): " EMAIL
    EMAIL=${EMAIL:-$DEFAULT_EMAIL}
    read -p "Enter proxy port (default: 8443): " PORT
    PORT=${PORT:-8443}
    read -p "Enter proxy username (default: admin): " USERNAME
    USERNAME=${USERNAME:-admin}
    read -s -p "Enter proxy password (will be randomly generated if left empty): " PASSWORD
    echo
    
    if [[ -z "$PASSWORD" ]]; then
        PASSWORD=$(openssl rand -base64 16)
        print_info "Generated random password: $PASSWORD"
    fi
    
    # Create configuration file
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "port": $PORT,
  "host": "0.0.0.0",
  "auth": {
    "enabled": true,
    "username": "$USERNAME",
    "password": "$PASSWORD"
  },
  "ssl": {
    "cert": "$SSL_DIR/fullchain.pem",
    "key": "$SSL_DIR/privkey.pem"
  },
  "domain": "$DOMAIN",
  "email": "$EMAIL",
  "logging": {
    "level": "info",
    "timestamp": true
  },
  "timeout": 30000
}
EOF
    
    chown "$USER:$GROUP" "$CONFIG_DIR/config.json"
    chmod 600 "$CONFIG_DIR/config.json"
    
    print_success "Configuration created at $CONFIG_DIR/config.json"
}

request_certificate() {
    local DOMAIN=$1
    local EMAIL=$2
    
    print_info "Requesting SSL certificate for $DOMAIN..."
    
    # Install acme.sh if not already installed
    install_acme "$EMAIL"
    
    # Stop any service using port 80
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    
    # Request certificate
    /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength 2048
    
    if [[ $? -eq 0 ]]; then
        # Install certificate
        /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
            --key-file "$SSL_DIR/privkey.pem" \
            --fullchain-file "$SSL_DIR/fullchain.pem" \
            --reloadcmd "systemctl reload bunproxy"
        
        # Set permissions
        chown -R "$USER:$GROUP" "$SSL_DIR"
        chmod -R 600 "$SSL_DIR"/*
        
        print_success "SSL certificate obtained and installed"
    else
        print_error "Failed to obtain SSL certificate"
        print_info "You can manually place your certificate files in $SSL_DIR/"
        print_info "Required files: fullchain.pem and privkey.pem"
    fi
}

setup_auto_renewal() {
    print_info "Setting up automatic certificate renewal..."
    
    # acme.sh already sets up a cron job for renewal
    print_success "Auto-renewal is configured via acme.sh cron job"
}

enable_service() {
    print_info "Enabling and starting BunProxy service..."
    
    systemctl daemon-reload
    systemctl enable bunproxy
    systemctl start bunproxy
    
    if systemctl is-active --quiet bunproxy; then
        print_success "BunProxy service is running"
    else
        print_error "Failed to start BunProxy service"
        echo "Check logs with: journalctl -u bunproxy -f"
        exit 1
    fi
}

print_summary() {
    local DOMAIN=$(grep -oP '"domain"\s*:\s*"\K[^"]+' "$CONFIG_DIR/config.json")
    local USERNAME=$(grep -oP '"username"\s*:\s*"\K[^"]+' "$CONFIG_DIR/config.json")
    local PASSWORD=$(grep -oP '"password"\s*:\s*"\K[^"]+' "$CONFIG_DIR/config.json")
    local PORT=$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CONFIG_DIR/config.json")
    
    echo
    echo "=========================================="
    print_success "BunProxy installation completed!"
    echo "=========================================="
    echo
    echo "Service status: $(systemctl is-active bunproxy)"
    echo "Configuration: $CONFIG_DIR/config.json"
    echo "SSL certificates: $SSL_DIR/"
    echo
    echo "Proxy URL: https://$USERNAME:$PASSWORD@$DOMAIN:$PORT"
    echo
    echo "Useful commands:"
    echo "  systemctl status bunproxy    # Check service status"
    echo "  systemctl restart bunproxy   # Restart service"
    echo "  journalctl -u bunproxy -f    # View logs"
    echo "  nano $CONFIG_DIR/config.json  # Edit configuration"
    echo
    echo "Built with Bun runtime for superior performance"
    echo
}

# Main installation flow
main() {
    print_info "Starting BunProxy installation..."
    
    check_root
    check_dependencies
    create_user
    create_directories
    install_files
    
    if [[ -f "$CONFIG_DIR/config.json" ]]; then
        print_info "Existing configuration found. Skipping interactive setup."
    else
        configure_proxy
    fi
    
    # Read domain and email from config
    local DOMAIN=$(grep -oP '"domain"\s*:\s*"\K[^"]+' "$CONFIG_DIR/config.json")
    local EMAIL=$(grep -oP '"email"\s*:\s*"\K[^"]+' "$CONFIG_DIR/config.json")
    
    # Ask if user wants to request certificate
    echo
    read -p "Do you want to automatically request an SSL certificate? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        request_certificate "$DOMAIN" "$EMAIL"
        setup_auto_renewal
    else
        print_info "Skipping certificate request. Please manually place your SSL files in $SSL_DIR/"
    fi
    
    enable_service
    print_summary
}

# Run main function
main "$@" 