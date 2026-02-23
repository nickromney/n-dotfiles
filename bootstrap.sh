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

# Install essential tools needed by install.sh and preferred workflow
echo "🔧 Installing essential tools..."
brew install yq      # Required by install.sh and Brewfile generation
brew install stow    # Required for symlink management
brew install mise    # Preferred runtime manager

if [[ -f "./Brewfile" ]]; then
    echo "📦 Installing Brewfile packages (preferred path)..."
    brew bundle --file ./Brewfile --no-lock
fi

echo "🟢 Installing runtimes via mise..."
mise install

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
echo "1. Run: make install           # Preferred install (Brewfile + mise + legacy bridge)"
echo "2. Run: make personal stow     # Stow configurations"
echo "3. Run: make personal configure # Apply macOS settings"
echo "4. Run: make focus-vscode      # If using VSCode"
echo "5. Run: make focus-neovim      # If using Neovim"
echo ""
echo "Legacy fallback (deprecated):"
echo "  ./install.sh -d"
echo "  ./install.sh"
