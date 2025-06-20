#!/bin/bash

# NodeProxy Test Script
# This script tests if the proxy is working correctly

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PROXY="https://127.0.0.1:8443"
DEFAULT_USERNAME="admin"

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if proxy URL is provided
if [ -z "$1" ]; then
    print_info "Usage: $0 [proxy_url] [username] [password]"
    print_info "Example: $0 https://proxy.example.com:8443 admin password123"
    echo
    read -p "Enter proxy URL (default: $DEFAULT_PROXY): " PROXY_URL
    PROXY_URL=${PROXY_URL:-$DEFAULT_PROXY}
    read -p "Enter username (default: $DEFAULT_USERNAME): " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
    read -s -p "Enter password: " PASSWORD
    echo
else
    PROXY_URL=$1
    USERNAME=${2:-$DEFAULT_USERNAME}
    PASSWORD=$3
fi

# Parse proxy URL
PROXY_HOST=$(echo $PROXY_URL | sed -e 's|https\?://||' -e 's|:.*||')
PROXY_PORT=$(echo $PROXY_URL | sed -e 's|.*:||')

echo
print_info "Testing NodeProxy at $PROXY_URL"
echo "=========================================="

# Test 1: Basic connectivity
print_info "Test 1: Basic connectivity"
if curl -k -s --proxy https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT https://httpbin.org/ip > /dev/null 2>&1; then
    print_success "Proxy is reachable"
else
    print_error "Cannot connect to proxy"
    echo "Please check:"
    echo "  - Proxy is running: systemctl status nodeproxy"
    echo "  - Firewall allows port $PROXY_PORT"
    echo "  - Credentials are correct"
    exit 1
fi

# Test 2: HTTP request
print_info "Test 2: HTTP request through proxy"
HTTP_RESPONSE=$(curl -k -s -w "\n%{http_code}" --proxy https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT http://httpbin.org/get)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
    print_success "HTTP requests work (Status: $HTTP_CODE)"
else
    print_error "HTTP request failed (Status: $HTTP_CODE)"
fi

# Test 3: HTTPS request
print_info "Test 3: HTTPS request through proxy"
HTTPS_RESPONSE=$(curl -k -s -w "\n%{http_code}" --proxy https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT https://httpbin.org/get)
HTTPS_CODE=$(echo "$HTTPS_RESPONSE" | tail -n1)
if [ "$HTTPS_CODE" = "200" ]; then
    print_success "HTTPS requests work (Status: $HTTPS_CODE)"
else
    print_error "HTTPS request failed (Status: $HTTPS_CODE)"
fi

# Test 4: IP check
print_info "Test 4: External IP check"
PROXY_IP=$(curl -k -s --proxy https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT https://httpbin.org/ip | grep -oP '"origin"\s*:\s*"\K[^"]+')
DIRECT_IP=$(curl -s https://httpbin.org/ip | grep -oP '"origin"\s*:\s*"\K[^"]+')

if [ ! -z "$PROXY_IP" ]; then
    print_success "Proxy IP: $PROXY_IP"
    if [ "$PROXY_IP" != "$DIRECT_IP" ]; then
        print_success "Traffic is being routed through proxy"
    else
        print_info "Proxy IP same as direct IP (might be expected if testing locally)"
    fi
else
    print_error "Could not determine proxy IP"
fi

# Test 5: Authentication
print_info "Test 5: Authentication check"
BAD_AUTH=$(curl -k -s -w "%{http_code}" -o /dev/null --proxy https://wronguser:wrongpass@$PROXY_HOST:$PROXY_PORT https://httpbin.org/ip)
if [ "$BAD_AUTH" = "407" ]; then
    print_success "Authentication is properly enforced"
else
    print_error "Authentication might not be working correctly"
fi

# Test 6: HTTP/2 support
print_info "Test 6: HTTP/2 support"
HTTP_VERSION=$(curl -k -s -w "%{http_version}" -o /dev/null --proxy https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT https://http2.pro/api/v1)
if [[ "$HTTP_VERSION" == "2" ]]; then
    print_success "HTTP/2 is supported"
elif [[ "$HTTP_VERSION" == "1.1" ]]; then
    print_info "Using HTTP/1.1 (HTTP/2 might not be available)"
else
    print_error "Unknown HTTP version: $HTTP_VERSION"
fi

# Test 7: Response time
print_info "Test 7: Performance test"
RESPONSE_TIME=$(curl -k -s -w "%{time_total}" -o /dev/null --proxy https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT https://httpbin.org/delay/1)
print_info "Response time for 1s delay endpoint: ${RESPONSE_TIME}s"

echo
echo "=========================================="
print_success "Proxy test completed!"
echo
echo "Configuration for applications:"
echo "  export https_proxy=https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT"
echo "  export http_proxy=https://$USERNAME:$PASSWORD@$PROXY_HOST:$PROXY_PORT"
echo