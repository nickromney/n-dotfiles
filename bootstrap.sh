#!/usr/bin/env bash
# Bootstrap script for fresh macOS installation
# This handles the chicken-and-egg problem of needing tools to install tools

set -euo pipefail

echo "🚀 Starting n-dotfiles bootstrap process..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This bootstrap script is designed for macOS only"
    exit 1
fi

# Create Developer directory structure
echo "📁 Creating Developer directory structure..."
mkdir -p "$HOME/Developer/personal"

# Install Homebrew if not present
if ! command -v brew >/dev/null 2>&1; then
    echo "🍺 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for this session
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "✓ Homebrew already installed"
fi

# Install essential tools needed by install.sh
echo "🔧 Installing essential tools..."
brew install yq      # Required by install.sh
brew install stow    # Required for symlink management

# Install 1Password early if needed for SSH
if [[ -n "${NON_INTERACTIVE:-}" ]]; then
    echo "Skipping 1Password installation (non-interactive mode)."
else
    read -p "Do you use 1Password for SSH keys? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔐 Installing 1Password..."
        brew install --cask 1password
        brew install --cask 1password-cli
    fi
fi

echo "✅ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "1. Run: ./install.sh -d        # Dry run to see what will be installed"
echo "2. Run: ./install.sh           # Install base tools"
echo "3. Run: ./install.sh -s        # Stow configurations"
echo "4. Run: make focus-vscode      # If using VSCode"
echo "5. Run: make focus-neovim      # If using Neovim"
echo ""
echo "Additional configurations available:"
echo "  ./install.sh -c shared/data-tools.yaml"
echo "  ./install.sh -c shared/file-tools.yaml"
echo "  ./install.sh -c shared/git.yaml"
echo "  ./install.sh -c shared/shell.yaml"
echo "  ./install.sh -c focus/python.yaml"
echo "  ./install.sh -c legacy/fonts.yaml"