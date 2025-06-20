#!/bin/bash

# NodeProxy Release Script
# This script builds binaries, creates archives, and generates checksums for a new release.

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${YELLOW}Info: $1${NC}"
}

print_success() {
    echo -e "${GREEN}Success: $1${NC}"
}

# --- Main Script ---

# 1. Get version from package.json
VERSION=$(grep -o '"version": "[^"]*"' package.json | head -1 | cut -d'"' -f4)
print_info "Preparing release for version: v$VERSION"

# 2. Clean previous builds
print_info "Cleaning up previous builds..."
rm -rf dist/
rm -rf release/
mkdir -p dist
mkdir -p release

# 3. Install dependencies
print_info "Installing Bun and dependencies..."
if ! command -v bun &> /dev/null; then
    print_info "Installing Bun globally..."
    curl -fsSL https://bun.sh/install | bash
fi

# 4. Build binary
print_info "Building binary with Bun..."
bun build ./nodeproxy.js --target=bun --compile --outfile=dist/nodeproxy
chmod +x dist/nodeproxy

# 5. Create release archive
print_info "Creating release archive..."
RELEASE_NAME="bunproxy-v$VERSION-linux"
RELEASE_DIR="release/$RELEASE_NAME"

# Create a temporary directory for the package contents
mkdir -p "$RELEASE_DIR"

# Copy necessary files
cp "dist/nodeproxy" "$RELEASE_DIR/nodeproxy"
cp install.sh "$RELEASE_DIR/"
cp uninstall.sh "$RELEASE_DIR/"
cp nodeproxy.service "$RELEASE_DIR/"
cp config.json.example "$RELEASE_DIR/"
cp README.md "$RELEASE_DIR/"
cp LICENSE "$RELEASE_DIR/"

# Create the tarball
(cd release && tar -czf "$RELEASE_NAME.tar.gz" "$RELEASE_NAME")

print_success "Created archive: release/$RELEASE_NAME.tar.gz"

# 6. Generate checksums
print_info "Generating checksums..."
(cd release && sha256sum *.tar.gz > "bunproxy-v$VERSION-checksums.txt")

# 7. Clean up intermediate directories
rm -rf release/bunproxy-v*
mv release/* .
rmdir release

print_info "Final release files are in the current directory."
ls -l bunproxy-v$VERSION-*.tar.gz

echo
print_success "Release v$VERSION is ready!"
print_info "Next steps:"
print_info "1. Create a new release on GitHub."
print_info "2. Upload the .tar.gz file and the checksums.txt file."
echo 