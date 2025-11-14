#!/usr/bin/env bash
# Universal GitHub Release Installer
# Usage: gh-install <repo-owner/repo-name> [binary-name]

set -e

VERSION="1.0.1"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
USER_INSTALL_DIR="$HOME/.local/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
    exit 1
}

usage() {
    cat << EOF
Universal GitHub Release Installer v${VERSION}

Usage: gh-install <owner/repo> [binary-name] [options]

Examples:
    gh-install gopasspw/gopass
    gh-install xo/usql usql

Options:
    -h, --help          Show help
    -v, --version VER   Specific version
    -u, --user          Install to ~/.local/bin
    --no-verify         Skip verification
EOF
    exit 0
}

detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case "$OS" in
        linux*)   OS="linux" ;;
        darwin*)  OS="darwin" ;;
        *) log_error "Unsupported OS: $OS" ;;
    esac
    
    case "$ARCH" in
        x86_64|amd64)   ARCH="amd64" ;;
        aarch64|arm64)  ARCH="arm64" ;;
        armv7*)         ARCH="armv7" ;;
        armv6*)         ARCH="armv6" ;;
        arm*)           ARCH="arm" ;;
        *) log_error "Unsupported arch: $ARCH" ;;
    esac
    
    log_info "Platform: ${OS}-${ARCH}"
}

get_version() {
    local repo=$1
    local version=$2
    
    if [ -z "$version" ] || [ "$version" = "latest" ]; then
        curl -sSL "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4
    else
        echo "$version"
    fi
}

find_asset() {
    local repo=$1
    local version=$2
    local os=$3
    local arch=$4
    
    local assets=$(curl -sSL "https://api.github.com/repos/${repo}/releases/tags/${version}" | grep 'browser_download_url' | cut -d'"' -f4)
    
    # Try different patterns
    local patterns=(
        "${os}-${arch}\.tar\.gz$"
        "${os}-${arch}\.tar\.bz2$"
        "${os}-${arch}\.zip$"
        "${os}_${arch}\.tar\.gz$"
        "${os}_${arch}\.deb$"
        "${os}_${arch}\.rpm$"
    )
    
    for pattern in "${patterns[@]}"; do
        local found=$(echo "$assets" | grep -iE "$pattern" | grep -iv "sbom\|sha\|sig" | head -n1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done
    
    # Fallback for arm variants
    if [ "$arch" = "arm64" ]; then
        local found=$(echo "$assets" | grep -iE "${os}.*arm.*64" | grep -E "\.tar\.(gz|bz2)$\|\.zip$" | grep -iv "sbom\|sha\|sig" | head -n1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    fi
    
    return 1
}

download_and_extract() {
    local url=$1
    local binary_name=$2
    local temp_dir=$(mktemp -d)
    
    cd "$temp_dir"
    
    local filename=$(basename "$url")
    
    curl -sSL "$url" -o "$filename" || log_error "Download failed"
    
    case "$filename" in
        *.tar.gz|*.tgz)
            tar xzf "$filename" ;;
        *.tar.bz2)
            tar xjf "$filename" ;;
        *.zip)
            unzip -q "$filename" ;;
        *.deb)
            sudo dpkg -i "$filename"
            rm -rf "$temp_dir"
            return 0
            ;;
        *.rpm)
            sudo rpm -i "$filename"
            rm -rf "$temp_dir"
            return 0
            ;;
    esac
    
    local binary_path=$(find . -type f -name "$binary_name" -o -name "${binary_name}.exe" | head -n1)
    
    if [ -z "$binary_path" ]; then
        log_error "Binary not found in archive"
    fi
    
    chmod +x "$binary_path"
    
    if [ -w "$INSTALL_DIR" ]; then
        mv "$binary_path" "$INSTALL_DIR/"
        log_info "Installed to: ${INSTALL_DIR}/${binary_name}"
    else
        if sudo -n true 2>/dev/null && [ "$USER_INSTALL" != "true" ]; then
            sudo mv "$binary_path" "$INSTALL_DIR/"
            log_info "Installed to: ${INSTALL_DIR}/${binary_name}"
        else
            mkdir -p "$USER_INSTALL_DIR"
            mv "$binary_path" "$USER_INSTALL_DIR/"
            log_info "Installed to: ${USER_INSTALL_DIR}/${binary_name}"
            
            if [[ ":$PATH:" != *":$USER_INSTALL_DIR:"* ]]; then
                log_warn "Add to PATH: export PATH=\"\$PATH:${USER_INSTALL_DIR}\""
            fi
        fi
    fi
    
    cd - > /dev/null
    rm -rf "$temp_dir"
}

install() {
    local repo=$1
    local binary_name=$2
    local version=$3
    
    if [ -z "$binary_name" ]; then
        binary_name=$(basename "$repo")
    fi
    
    detect_platform
    
    log_info "Fetching version info..."
    local release_version=$(get_version "$repo" "$version")
    if [ -z "$release_version" ]; then
        log_error "Failed to get version"
    fi
    log_info "Version: ${release_version}"
    
    log_info "Finding asset..."
    local asset_url=$(find_asset "$repo" "$release_version" "$OS" "$ARCH")
    if [ -z "$asset_url" ]; then
        log_error "No asset found for ${OS}-${ARCH}"
    fi
    
    log_info "Downloading..."
    download_and_extract "$asset_url" "$binary_name"
    
    if command -v "$binary_name" &> /dev/null; then
        log_info "Success: $binary_name installed"
        "$binary_name" --version 2>/dev/null || "$binary_name" version 2>/dev/null || true
    else
        log_warn "Installed but not in PATH. Run: hash -r"
    fi
}

# Parse args
REPO=""
BINARY_NAME=""
VERSION="latest"
USER_INSTALL="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage ;;
        -v|--version) VERSION="$2"; shift 2 ;;
        -u|--user) USER_INSTALL="true"; INSTALL_DIR="$USER_INSTALL_DIR"; shift ;;
        *) 
            if [ -z "$REPO" ]; then REPO="$1"
            elif [ -z "$BINARY_NAME" ]; then BINARY_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$REPO" ]; then
    log_error "Usage: gh-install <owner/repo> [binary]"
fi

for cmd in curl tar; do
    if ! command -v $cmd &> /dev/null; then
        log_error "Required: $cmd"
    fi
done

install "$REPO" "$BINARY_NAME" "$VERSION"
