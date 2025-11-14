#!/usr/bin/env bash
# Universal GitHub Release Installer
# Usage: gh-install <repo-owner/repo-name> [binary-name]
# Example: gh-install gopasspw/gopass
# Example: gh-install xo/usql usql

set -e

VERSION="1.0.0"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
USER_INSTALL_DIR="$HOME/.local/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

# Show usage
usage() {
    cat << EOF
Universal GitHub Release Installer v${VERSION}

Usage:
    gh-install <owner/repo> [binary-name] [options]

Examples:
    gh-install gopasspw/gopass
    gh-install xo/usql usql
    gh-install cli/cli gh

Options:
    -h, --help              Show this help message
    -v, --version VERSION   Install specific version (default: latest)
    -d, --dir DIR          Installation directory (default: /usr/local/bin)
    -u, --user             Install to user directory (~/.local/bin)
    --no-verify            Skip installation verification

Environment Variables:
    INSTALL_DIR            Custom installation directory
    GITHUB_TOKEN           GitHub API token (for private repos or rate limits)

EOF
    exit 0
}

# Detect OS and Architecture
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case "$OS" in
        linux*)   OS="linux" ;;
        darwin*)  OS="darwin" ;;
        freebsd*) OS="freebsd" ;;
        openbsd*) OS="openbsd" ;;
        mingw*|msys*|cygwin*) OS="windows" ;;
        *) log_error "Unsupported OS: $OS" ;;
    esac
    
    case "$ARCH" in
        x86_64|amd64)         ARCH="amd64" ;;
        aarch64|arm64)        ARCH="arm64" ;;
        armv7l|armv7)         ARCH="arm" ;;
        armv6l|armv6)         ARCH="arm" ;;
        i386|i686)            ARCH="386" ;;
        *) log_error "Unsupported architecture: $ARCH" ;;
    esac
    
    log_info "Detected platform: ${OS}-${ARCH}"
}

# Get GitHub API headers
get_github_headers() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "Authorization: token $GITHUB_TOKEN"
    fi
}

# Get latest or specific version
get_version() {
    local repo=$1
    local version=$2
    
    if [ -z "$version" ] || [ "$version" = "latest" ]; then
        log_info "Fetching latest release info for ${repo}..."
        curl -sS $([ -n "$GITHUB_TOKEN" ] && echo "-H \"Authorization: token $GITHUB_TOKEN\"") \
            "https://api.github.com/repos/${repo}/releases/latest" \
            | jq -r '.tag_name'
    else
        echo "$version"
    fi
}

# Find best matching asset
find_asset() {
    local repo=$1
    local version=$2
    local os=$3
    local arch=$4
    
    log_info "Searching for ${os}-${arch} binary..."
    
    # Get all assets
    local assets=$(curl -sS $([ -n "$GITHUB_TOKEN" ] && echo "-H \"Authorization: token $GITHUB_TOKEN\"") \
        "https://api.github.com/repos/${repo}/releases/tags/${version}" \
        | jq -r '.assets[].browser_download_url')
    
    # Filter patterns (in priority order)
    local patterns=(
        "${os}-${arch}\.(tar\.gz|tgz)$"
        "${os}-${arch}\.tar\.bz2$"
        "${os}-${arch}\.zip$"
        "${os}_${arch}\.(tar\.gz|tgz)$"
        "${os}_${arch}\.tar\.bz2$"
        "${os}_${arch}\.zip$"
        "${os}.*${arch}\.(tar\.gz|tgz|tar\.bz2|zip)$"
        "_${os}_${arch}\.(tar\.gz|tgz|tar\.bz2|zip|deb|rpm)$"
    )
    
    # Special handling for debian packages
    if [ "$os" = "linux" ] && command -v dpkg &> /dev/null; then
        patterns+=("_${arch}\.deb$")
    fi
    
    # Special handling for rpm packages
    if [ "$os" = "linux" ] && command -v rpm &> /dev/null; then
        patterns+=("_${arch}\.rpm$")
    fi
    
    # Try each pattern
    for pattern in "${patterns[@]}"; do
        local found=$(echo "$assets" | grep -iE "$pattern" | grep -iv "sbom\|sha\|sig\|asc\|checksum" | head -n1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done
    
    # Fallback: universal binaries (macOS)
    if [ "$os" = "darwin" ]; then
        local found=$(echo "$assets" | grep -iE "darwin.*universal\.(tar\.gz|tgz|tar\.bz2|zip)$" | head -n1)
        if [ -n "$found" ]; then
            log_warn "Using universal binary for macOS"
            echo "$found"
            return 0
        fi
    fi
    
    log_error "No suitable binary found for ${os}-${arch}"
}

# Download and extract
download_and_extract() {
    local url=$1
    local binary_name=$2
    local temp_dir=$(mktemp -d)
    
    log_info "Downloading from: ${url}"
    
    cd "$temp_dir"
    
    # Determine file type
    local filename=$(basename "$url")
    local extension="${filename##*.}"
    
    if [[ "$filename" == *.tar.gz ]] || [[ "$filename" == *.tgz ]]; then
        extension="tar.gz"
    elif [[ "$filename" == *.tar.bz2 ]]; then
        extension="tar.bz2"
    fi
    
    # Download
    curl -L --progress-bar -o "$filename" "$url" || log_error "Download failed"
    
    # Extract based on extension
    case "$extension" in
        tar.gz|tgz)
            tar xzf "$filename" || log_error "Extraction failed"
            ;;
        tar.bz2)
            tar xjf "$filename" || log_error "Extraction failed"
            ;;
        zip)
            unzip -q "$filename" || log_error "Extraction failed"
            ;;
        deb)
            log_info "Installing .deb package..."
            sudo dpkg -i "$filename" || log_error "Package installation failed"
            rm -rf "$temp_dir"
            return 0
            ;;
        rpm)
            log_info "Installing .rpm package..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y "$filename" || log_error "Package installation failed"
            else
                sudo rpm -i "$filename" || log_error "Package installation failed"
            fi
            rm -rf "$temp_dir"
            return 0
            ;;
        *)
            log_error "Unsupported file format: $extension"
            ;;
    esac
    
    # Find binary (handle nested directories)
    local binary_path=$(find . -type f -name "$binary_name" -o -name "${binary_name}.exe" | head -n1)
    
    if [ -z "$binary_path" ]; then
        log_error "Binary '$binary_name' not found in archive"
    fi
    
    chmod +x "$binary_path"
    
    # Install
    if [ -w "$INSTALL_DIR" ]; then
        mv "$binary_path" "$INSTALL_DIR/" || log_error "Installation failed"
        log_info "Installed to: ${INSTALL_DIR}/${binary_name}"
    else
        sudo mv "$binary_path" "$INSTALL_DIR/" 2>/dev/null || {
            mkdir -p "$USER_INSTALL_DIR"
            mv "$binary_path" "$USER_INSTALL_DIR/"
            log_info "Installed to: ${USER_INSTALL_DIR}/${binary_name}"
            
            # Add to PATH if not already there
            if [[ ":$PATH:" != *":$USER_INSTALL_DIR:"* ]]; then
                log_warn "Add to your PATH: export PATH=\"\$PATH:${USER_INSTALL_DIR}\""
                echo "export PATH=\"\$PATH:${USER_INSTALL_DIR}\"" >> ~/.bashrc
            fi
        }
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Main installation function
install() {
    local repo=$1
    local binary_name=$2
    local version=$3
    local verify=${4:-true}
    
    # Extract binary name from repo if not provided
    if [ -z "$binary_name" ]; then
        binary_name=$(basename "$repo")
    fi
    
    detect_platform
    
    # Get version
    local release_version=$(get_version "$repo" "$version")
    if [ -z "$release_version" ]; then
        log_error "Failed to get release version"
    fi
    log_info "Version: ${release_version}"
    
    # Find asset
    local asset_url=$(find_asset "$repo" "$release_version" "$OS" "$ARCH")
    if [ -z "$asset_url" ]; then
        log_error "No suitable asset found"
    fi
    
    # Download and install
    download_and_extract "$asset_url" "$binary_name"
    
    # Verify installation
    if [ "$verify" = true ]; then
        log_info "Verifying installation..."
        if command -v "$binary_name" &> /dev/null; then
            log_info "Successfully installed: $binary_name"
            "$binary_name" --version 2>/dev/null || "$binary_name" version 2>/dev/null || log_info "Binary is executable"
        else
            log_warn "Binary installed but not in PATH. Try: hash -r"
        fi
    fi
}

# Parse arguments
REPO=""
BINARY_NAME=""
VERSION="latest"
VERIFY=true
USER_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -u|--user)
            INSTALL_DIR="$USER_INSTALL_DIR"
            USER_INSTALL=true
            shift
            ;;
        --no-verify)
            VERIFY=false
            shift
            ;;
        *)
            if [ -z "$REPO" ]; then
                REPO="$1"
            elif [ -z "$BINARY_NAME" ]; then
                BINARY_NAME="$1"
            else
                log_error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate
if [ -z "$REPO" ]; then
    log_error "Repository not specified. Usage: gh-install <owner/repo>"
fi

# Check dependencies
for cmd in curl jq tar; do
    if ! command -v $cmd &> /dev/null; then
        log_error "Required command not found: $cmd"
    fi
done

# Run installation
install "$REPO" "$BINARY_NAME" "$VERSION" "$VERIFY"
