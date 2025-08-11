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

section "Personal Mac Setup"

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

# Step 3: Install personal-specific packages if config exists
if [[ -f "_configs/host/personal.yaml" ]]; then
  section "Installing personal-specific packages"
  info "Installing packages from host/personal configuration..."
  if ! CONFIG_FILES="host/personal" ./install.sh; then
    error "Personal package installation failed"
    exit 1
  fi
  success "Personal packages installed"
else
  warning "No personal-specific configuration found at _configs/host/personal.yaml"
fi

# Step 3b: Check for manual installation requirements
if [[ -f "_configs/host/manual-check.yaml" ]]; then
  section "Checking manually installed applications"
  info "Checking for required manual installations..."
  if ! CONFIG_FILES="host/manual-check" ./install.sh; then
    warning "Some manual applications may be missing"
  fi
fi

# Step 4: Apply macOS system settings
section "Applying macOS system settings"
if [[ -f "_macos/personal.yaml" ]]; then
  info "Applying personal macOS settings..."
  if ! ./_macos/macos.sh _macos/personal.yaml; then
    error "macOS configuration failed"
    exit 1
  fi
  success "macOS settings applied"
else
  warning "No personal macOS configuration found at _macos/personal.yaml"
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

# Step 7: SSH Setup from 1Password
section "SSH Configuration"
if [[ -f "./setup-ssh-from-1password.sh" ]] && command -v op >/dev/null 2>&1; then
  info "Setting up SSH configuration and keys from 1Password..."
  if ./setup-ssh-from-1password.sh; then
    success "SSH configuration completed"
  else
    warning "SSH setup encountered issues - you may need to run ./setup-ssh-from-1password.sh manually"
  fi
else
  warning "1Password CLI not found or SSH setup script missing"
  echo "  To set up SSH later, run: ./setup-ssh-from-1password.sh"
fi

# Step 8: Additional setup reminders
section "Setup Complete!"
success "Personal Mac setup completed successfully"
echo
info "Next steps:"
echo "  1. Restart your terminal to load new shell configurations"
echo "  2. Sign in to 1Password if not already done"
echo "  3. Configure git with your personal email: git config --global user.email 'your-email@domain.com'"
echo "  4. Verify SSH keys are working: ssh -T git@github.com"
echo "  5. Sign into Mac App Store and re-run if any mas apps failed"
echo "  6. Install any manually tracked apps shown above (Snagit, Camtasia, etc.)"
echo
info "You may also want to:"
echo "  - Run 'make update' periodically to keep tools up to date"
echo "  - Run 'make personal' to reinstall any missing packages"