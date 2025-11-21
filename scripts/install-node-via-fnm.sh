#!/usr/bin/env bash
#
# Install Node.js LTS via fnm (Fast Node Manager)
#
# This script installs the latest LTS version of Node.js using fnm.
# It's designed to be called after fnm is installed via Homebrew.

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() {
  echo -e "${GREEN}$1${NC}"
}

warn() {
  echo -e "${YELLOW}$1${NC}"
}

error() {
  echo -e "${RED}$1${NC}"
}

# Check if fnm is installed
if ! command -v fnm >/dev/null 2>&1; then
  error "fnm is not installed."
  error "Run: brew install fnm"
  exit 1
fi

# Check if node is already installed via fnm
if command -v node >/dev/null 2>&1 && [[ "$(command -v node)" == *"fnm"* ]]; then
  CURRENT_VERSION=$(node --version)
  warn "Node.js is already installed via fnm: $CURRENT_VERSION"
  read -rp "Do you want to install/update to the latest LTS? (y/N) " -n 1
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Skipping Node.js installation."
    exit 0
  fi
fi

# Install Node.js LTS
info "Installing Node.js LTS via fnm..."
fnm install --lts

# Set the installed version as default
info "Setting LTS as default Node.js version..."
fnm default lts-latest

# Verify installation
# Need to eval fnm env to make node available in this script
eval "$(fnm env --shell bash)"

if command -v node >/dev/null 2>&1; then
  NODE_VERSION=$(node --version)
  NPM_VERSION=$(npm --version)
  info "✓ Node.js installed successfully!"
  info "  Node.js version: $NODE_VERSION"
  info "  npm version: $NPM_VERSION"
else
  error "Failed to install Node.js via fnm"
  exit 1
fi

info ""
info "Note: You may need to restart your shell or run:"
info "  For zsh: source ~/.zshrc"
info "  For nushell: restart nu"
