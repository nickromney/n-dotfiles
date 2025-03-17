# ZSH Configuration

This directory contains my ZSH shell configuration files, managed with GNU Stow.

## Files

- `.zshrc` - Main configuration file loaded for interactive shells
- `.zshenv` - Environment variables loaded for all ZSH sessions (including non-interactive)

## Key Features

### History Management

The configuration sets up extensive history with 100,000 entries and several optimisations:

- Ignores duplicate consecutive commands
- Ignores commands starting with spaces
- Saves history incrementally (so it's available across terminal sessions immediately)

### Enhanced Navigation

#### Keyboard Shortcuts

- **Word Navigation**:
  - macOS: Option+Left/Right jumps between words
  - Linux/Other: Ctrl+Left/Right jumps between words
- **Line Navigation**:
  - Ctrl+A: Jump to start of line
  - Ctrl+E: Jump to end of line
  - Home/End keys are properly mapped

#### Smart History Search

- **Up/Down Arrow** keys are mapped to `history-beginning-search-backward/forward`
  - This means if you type part of a command and press Up, it finds commands in your history that start with what you've typed
  - Much more efficient than cycling through your entire history

### Conditional Tool Loading

The configuration dynamically adapts based on which tools are installed:

- **Zoxide** (smart cd command) is used if available
- **FZF** (fuzzy finder) with optimizations if available
- **Starship** prompt if available
- **NVM** (Node Version Manager) if installed via Homebrew
- Plugins like **zsh-autosuggestions** and **zsh-syntax-highlighting** if available

### Smart Aliases

Aliases are created conditionally based on available tools:

- **Navigation**:
  - `o`: Alias for `z` (zoxide) if available
  - `cdd`: Navigate to Developer directory using zoxide if available, or regular cd as fallback
- **Git**:
  - `g`: Opens lazygit if available
  - `gs`: Git status
  - `gc`: Git commit
- **File Listing**:
  - `l`: Uses eza if available, falls back to ls
  - `tree`: Uses eza's tree view if available
- **Editors**:
  - `n`: Opens neovim
- **FZF Combinations**:
  - `bf`: Use fzf+bat to select and display files
  - `nf`: Use fzf to select a file and open in neovim
  - `pf`: Use fzf to select a file and copy path to clipboard

### Path Management

- Adds several directories to PATH if they exist
- Removes duplicates from PATH to prevent bloat
- Properly handles Podman socket for Docker compatibility

### SSL Certificate Handling

- Sets up ZScaler certificates if present for various tools

## Customisation

For local customisations that shouldn't be tracked in version control, you can create:

- `~/.local/bin/env` - This file will be sourced if it exists
