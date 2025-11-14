#!/usr/bin/env bash
set -e

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
USER_INSTALL_DIR="$HOME/.local/bin"

log() { echo -e "\033[0;32m✓\033[0m $1" >&2; }
err() { echo -e "\033[0;31m✗\033[0m $1" >&2; exit 1; }

detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case "$OS" in
        linux*) OS="linux" ;;
        darwin*) OS="darwin" ;;
        *) err "Unsupported OS: $OS" ;;
    esac
    
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7*) ARCH="armv7" ;;
        armv6*) ARCH="armv6" ;;
        *) err "Unsupported arch: $ARCH" ;;
    esac
    
    log "Platform: ${OS}-${ARCH}"
}

get_version() {
    curl -sSL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name"' | cut -d'"' -f4
}

find_asset() {
    local repo=$1 version=$2 os=$3 arch=$4
    local assets=$(curl -sSL "https://api.github.com/repos/${repo}/releases/tags/${version}" | grep 'browser_download_url' | cut -d'"' -f4)
    
    for pattern in "${os}-${arch}\.tar\.gz$" "${os}-${arch}\.tar\.bz2$" "${os}_${arch}\.tar\.gz$" "${os}_${arch}\.deb$"; do
        local found=$(echo "$assets" | grep -iE "$pattern" | grep -iv "sbom\|sha\|sig" | head -n1)
        [ -n "$found" ] && { echo "$found"; return 0; }
    done
    
    return 1
}

install() {
    local repo=$1 binary=${2:-$(basename "$1")}
    
    detect_platform
    
    local version=$(get_version "$repo")
    [ -z "$version" ] && err "Failed to get version"
    log "Version: ${version}"
    
    local url=$(find_asset "$repo" "$version" "$OS" "$ARCH")
    [ -z "$url" ] && err "No binary found for ${OS}-${ARCH}"
    log "Found: $(basename "$url")"
    
    local tmp=$(mktemp -d)
    cd "$tmp"
    
    curl -sSL "$url" -o package || err "Download failed"
    
    case "$url" in
        *.tar.gz) tar xzf package ;;
        *.tar.bz2) tar xjf package ;;
        *.deb) sudo dpkg -i package; rm -rf "$tmp"; return 0 ;;
    esac
    
    local bin=$(find . -type f -name "$binary" | head -n1)
    [ -z "$bin" ] && err "Binary not found"
    
    chmod +x "$bin"
    
    mkdir -p "$INSTALL_DIR"
    if mv "$bin" "$INSTALL_DIR/" 2>/dev/null || sudo mv "$bin" "$INSTALL_DIR/" 2>/dev/null; then
        log "Installed: ${INSTALL_DIR}/${binary}"
    else
        err "Install failed"
    fi
    
    rm -rf "$tmp"
    command -v "$binary" >/dev/null && log "Success!"
}

REPO="" BINARY="" USER_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user) INSTALL_DIR="$USER_INSTALL_DIR"; USER_INSTALL=true; shift ;;
        *) [ -z "$REPO" ] && REPO="$1" || BINARY="$1"; shift ;;
    esac
done

[ -z "$REPO" ] && err "Usage: gh-install owner/repo [binary] [--user]"

install "$REPO" "$BINARY"
