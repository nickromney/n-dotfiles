#!/usr/bin/env bash
#
# Install Node.js LTS via nvm
#
# This script sources nvm and installs the latest LTS version of Node.js.
# It's designed to be called after nvm is installed via Homebrew.

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

# Check if nvm is installed via Homebrew
if ! command -v brew >/dev/null 2>&1; then
  error "Homebrew is not installed. Please install Homebrew first."
  exit 1
fi

NVM_DIR="$(brew --prefix nvm 2>/dev/null || echo "")"
if [ -z "$NVM_DIR" ] || [ ! -d "$NVM_DIR" ]; then
  error "nvm is not installed via Homebrew."
  error "Run: brew install nvm"
  exit 1
fi

# Source nvm
info "Sourcing nvm from $NVM_DIR..."
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Verify nvm is available
if ! type nvm >/dev/null 2>&1; then
  error "Failed to load nvm. Please check your nvm installation."
  exit 1
fi

# Check if node is already installed
if command -v node >/dev/null 2>&1; then
  CURRENT_VERSION=$(node --version)
  warn "Node.js is already installed: $CURRENT_VERSION"
  read -rp "Do you want to install/update to the latest LTS? (y/N) " -n 1
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Skipping Node.js installation."
    exit 0
  fi
fi

# Install Node.js LTS
info "Installing Node.js LTS via nvm..."
nvm install --lts

# Set the installed version as default
info "Setting LTS as default Node.js version..."
nvm alias default 'lts/*'

# Verify installation
if command -v node >/dev/null 2>&1; then
  NODE_VERSION=$(node --version)
  NPM_VERSION=$(npm --version)
  info "✓ Node.js installed successfully!"
  info "  Node.js version: $NODE_VERSION"
  info "  npm version: $NPM_VERSION"
else
  error "Failed to install Node.js via nvm"
  exit 1
fi

info ""
info "Note: You may need to restart your shell or run:"
info "  source ~/.zshrc"
