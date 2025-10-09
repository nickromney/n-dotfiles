#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

error() {
  echo -e "${RED}✗${NC} $*" >&2
}

section() {
  echo
  echo -e "${GREEN}=== $* ===${NC}"
  echo
}

# Check if we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  error "This script is for macOS only"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

section "Work Mac Setup"

# Step 1: Run bootstrap if needed
if ! command -v brew >/dev/null 2>&1 || ! command -v yq >/dev/null 2>&1 || ! command -v stow >/dev/null 2>&1; then
  info "Running bootstrap to install essential tools..."
  if ! ./bootstrap.sh; then
    error "Bootstrap failed"
    exit 1
  fi
  success "Bootstrap completed"
else
  success "Essential tools already installed"
fi

# Step 2: Install shared and common packages
section "Installing shared and common packages"
info "Installing packages from shared and host/common configurations..."
# Using the same pattern as Makefile's COMMON_CONFIGS
if ! CONFIG_FILES="shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common" ./install.sh; then
  error "Package installation failed"
  exit 1
fi
success "Packages installed"

# Step 3: Install work-specific packages if config exists
if [[ -f "_configs/host/work.yaml" ]]; then
  section "Installing work-specific packages"
  info "Installing packages from host/work configuration..."
  if ! CONFIG_FILES="host/work" ./install.sh; then
    error "Work package installation failed"
    exit 1
  fi
  success "Work packages installed"
else
  warning "No work-specific configuration found at _configs/host/work.yaml"
fi

# Step 4: Apply macOS system settings
section "Applying macOS system settings"
if [[ -f "_macos/work.yaml" ]]; then
  info "Applying work macOS settings..."
  if ! ./_macos/macos.sh _macos/work.yaml; then
    error "macOS configuration failed"
    exit 1
  fi
  success "macOS settings applied"
else
  warning "No work macOS configuration found at _macos/work.yaml"
  info "You may want to create one based on _macos/personal.yaml"
fi

# Step 5: Stow configurations
section "Creating configuration symlinks"
info "Running stow to create symlinks..."
if ! ./install.sh -s; then
  error "Stow failed"
  exit 1
fi
success "Configuration symlinks created"

# Step 6: Install VSCode extensions
section "Installing VSCode extensions"
if command -v code >/dev/null 2>&1; then
  info "Installing VSCode extensions..."
  if ! CONFIG_FILES="focus/vscode" ./install.sh; then
    warning "Some VSCode extensions may have failed to install"
  else
    success "VSCode extensions installed"
  fi
else
  warning "VSCode not found, skipping extensions"
fi

# Step 7: Additional setup reminders
section "Setup Complete!"
success "Work Mac setup completed successfully"
echo
info "Next steps:"
echo "  1. Restart your terminal to load new shell configurations"
echo "  2. Sign in to 1Password if not already done"
echo "  3. Configure git with your work email: git config --global user.email 'your-work-email@company.com'"
echo "  4. Set up SSH keys for GitHub/GitLab access"
echo "  5. Install any company-specific tools or certificates"
echo
info "You may also want to:"
echo "  - Create a work-specific macOS configuration at _macos/work.yaml"
echo "  - Create a work-specific tools configuration at _configs/host/work.yaml"
echo "  - Run 'make update' periodically to keep tools up to date"
