# ZSH Configuration

This directory contains my ZSH shell configuration files, managed with GNU Stow.

## Startup Performance

### Measuring Startup Time

```bash
# Quick measurement (5 runs)
for i in {1..5}; do /usr/bin/time zsh -i -c exit 2>&1; done

# Detailed benchmark with hyperfine (recommended)
hyperfine --warmup 3 --runs 10 'zsh -i -c exit'

# Profile what's taking time (creates ~/.zsh_profile.log)
# Add to top of .zshrc: zmodload zsh/zprof
# Add to bottom of .zshrc: zprof > ~/.zsh_profile.log
```

### Performance History

| Date | Mean | Range | Notes |
|------|------|-------|-------|
| 2025-11-26 | 150.9ms ± 1.0ms | 149-153ms | Baseline before optimisation |
| 2025-11-26 | 108.9ms ± 0.9ms | 108-111ms | Cache BREW_PREFIX (was called 3x) |
| 2025-11-26 | 121.6ms ± 1.2ms | 120-123ms | Cache tool init scripts + added uv & direnv |
| 2025-11-26 | 102.1ms ± 1.1ms | 100-104ms | Cache kubectl completion (was ~19ms per startup) |

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

### Defensive Programming

The configuration is **fully modular and defensive** - every tool invocation checks for existence first using `command -v`. This ensures the configuration works across different environments:

- Personal Mac (all tools installed)
- Work Mac (minimal tools)
- Fresh installations (missing optional tools)
- Dev containers (restricted environments)

All tool-specific features (completions, plugins, integrations) are wrapped in conditional checks, so missing tools never cause errors.

### Conditional Tool Loading

The configuration dynamically adapts based on which tools are installed:

- **Zoxide** (smart cd command) is used if available
- **FZF** (fuzzy finder) with optimizations if available
- **Starship** prompt if available
- **fnm** (Fast Node Manager) if installed via Homebrew
- **kubectl** completions and aliases if available
- **direnv** integration if available
- Plugins like **zsh-autosuggestions** and **zsh-syntax-highlighting** if available via Homebrew

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
- **FZF Combinations** (fuzzy file finding with preview):
  - `f`: Launch fzf fuzzy finder
  - `bf`: Select file with preview, open in bat pager
  - `nf`: Select file with preview, open in neovim
  - `pf`: Select file with preview, copy path to clipboard

  All fzf commands use bat for syntax-highlighted previews with line numbers (first 500 lines)

### Path Management

- Adds several directories to PATH if they exist
- Removes duplicates from PATH to prevent bloat
- Properly handles Podman socket for Docker compatibility

### SSL Certificate Handling

- Sets up ZScaler certificates if present for various tools

## Customisation

For local customisations that shouldn't be tracked in version control, you can create:

- `~/.local/bin/env` - This file will be sourced if it exists
