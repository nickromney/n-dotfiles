# n-dotfiles

An opinionated dotfiles setup designed to:

- work on Mac OS X with brew
- work on Ubuntu (particularly in dev containers and for GitHub Actions)
- be extensible to add other package managers

## Design considerations

- I work on Mac OS X
- I'm trying to move to use dev containers
- I'm a DevOps Engineer by recent training, so like idempotent code

I looked at [nix flakes](https://nixos.wiki/wiki/flakes) but although I'm often tweaking my configuration, I don't need to set up whole new machines enough to warrant it. This [blog](https://jvns.ca/blog/2023/11/11/notes-on-nix-flakes/) from Julia Evans convinced me away from it.

## Quick Start

```bash
# Clone and enter directory
git clone https://github.com/nickromney/n-dotfiles.git ~/n-dotfiles
cd ~/n-dotfiles

# Install common Mac tools (recommended starting point)
make common install

# Or install my personal setup (includes VSCode extensions)
make personal stow

# Or just install VSCode and extensions
make focus-vscode
```

## Using the Makefile

The Makefile provides convenient targets for different configurations:

```bash
# Main targets
make common       # Essential Mac tools (shared + host/common)
make personal     # My personal machine setup
make work         # Work machine setup

# Focus targets (specific tool categories)
make focus-vscode     # VSCode and extensions
make focus-devops     # DevOps tools
make focus-neovim     # Neovim and plugins

# Actions (combine with targets)
make personal install  # Install packages only
make personal update   # Update existing packages
make personal stow     # Install and create symlinks

# VSCode for different editors
VSCODE_CLI=cursor make focus-vscode  # Install extensions for Cursor
```

## Features

- Automatically detects available package managers
- Skips unavailable package managers without failing
- Installs only tools that match available package managers
- Uses GNU Stow for configuration management
- Force mode (`-f`) to handle existing configurations

## Usage

### Package Installation and Configuration

```bash
# Install packages only
./install.sh

# Install packages and stow configurations
./install.sh -s

# Preview changes without making them
./install.sh -d -s

# Force stow to adopt existing files
./install.sh -s -f

# Update installed packages
./install.sh -u
```

### macOS System Configuration

Light-touch macOS configuration management:

```bash
# Show current system settings
./_macos/macos.sh

# Apply personal configuration
./_macos/macos.sh personal.yaml

# Dry run to preview changes
./_macos/macos.sh -d personal.yaml
```

See [_macos/README.md](_macos/README.md) for detailed macOS configuration options.

## Configuration Structure

The `_configs/` directory uses a layered approach:

```
_configs/
├── shared/           # Cross-platform tools
│   ├── shell.yaml        # Shell utilities (zsh, starship, etc.)
│   ├── git.yaml          # Git tools
│   ├── search.yaml       # Search tools (ripgrep, fzf, etc.)
│   ├── neovim.yaml       # Neovim configuration
│   ├── file-tools.yaml   # File management utilities
│   ├── data-tools.yaml   # Data processing tools
│   └── network.yaml      # Network utilities
├── host/             # Host-specific configurations  
│   ├── common.yaml       # Tools for any Mac (Ghostty, VSCode, Obsidian, etc.)
│   ├── personal.yaml     # Personal additions
│   └── work.yaml         # Work-specific tools
└── focus/            # Development focus areas
    ├── vscode.yaml       # VSCode + 38 extensions
    ├── python.yaml       # Python development
    ├── typescript.yaml   # TypeScript/Node development
    ├── rust.yaml         # Rust development
    ├── kubernetes.yaml   # Kubernetes tools
    └── container-base.yaml  # Base container tools

### Package Manager Examples

### Tap a Homebrew repository

```yaml
noahgorstein/tap:
  manager: brew
  type: tap
  check_command: "brew tap | grep -q '^noahgorstein/tap$'"
  install_args: []
```

### Install a Homebrew cask application

```yaml
kitty:
  manager: brew
  type: cask
  check_command: 'brew list --cask kitty >/dev/null 2>&1 || [ -d "/Applications/kitty.app" ] || which kitty >/dev/null 2>&1'
  install_args: []
```

### Install a Homebrew package

```yaml
bat:
  manager: brew
  type: package
  check_command: "bat --version"
  install_args: []
```

### Install a tool via arkade

```yaml
atuin:
  manager: arkade
  type: get
  check_command: "test -f $HOME/.arkade/bin/atuin"
  install_args: []
```

### Install a Python tool via uv

```yaml
posting:
  manager: uv
  type: tool
  check_command: "which posting >/dev/null 2>&1"
  install_args: ["--python", "3.12"]
```

### Install VSCode extensions

```yaml
prettier-vscode:
  manager: code
  type: extension
  extension_id: esbenp.prettier-vscode
  check_command: "code --list-extensions | grep -q esbenp.prettier-vscode"
  description: "Code formatter"
  documentation_url: "https://prettier.io/"
  category: vscode-extension
```

Each tool entry requires:

```yaml
manager: Package manager to use (brew/arkade/uv/cargo/apt/code)
type: Installation method specific to the manager
check_command: Command to verify installation
install_args: Additional installation arguments (optional)
extension_id: Required for VSCode extensions (manager: code)
```

### VSCode Extension Management

The `code` package manager supports VSCode and compatible editors:

```bash
# Default: uses 'code' CLI
make focus-vscode

# For Cursor editor
VSCODE_CLI=cursor make focus-vscode

# For VSCodium
VSCODE_CLI=vscodium make focus-vscode
```

## Directory Structure

```shell
.
├── install.sh      # Main installation script
├── Makefile        # Convenient targets for common operations
├── _configs/       # Modular configuration files
│   ├── shared/     # Cross-platform tools
│   ├── host/       # Host-specific configurations
│   └── focus/      # Development focus areas
├── _macos/         # macOS system configuration
│   ├── macos.sh    # macOS settings script
│   └── *.yaml      # Settings profiles
├── _test/          # Comprehensive test suite
│   ├── install.bats     # Installation tests
│   ├── macos.bats       # macOS tests
│   ├── makefile.bats    # Makefile tests
│   └── run_tests.sh     # Test runner
└── */              # Stow directories for dotfiles
    ├── aerospace/  # Tiling window manager
    ├── git/        # Git configuration
    ├── nvim/       # Neovim config
    ├── tmux/       # Tmux config
    ├── vscode/     # VSCode settings
    ├── zsh/        # Zsh configuration
    └── ...         # Other tool configs
```

## Testing

The repository includes a comprehensive test suite using BATS (Bash Automated Testing System):

```bash
# Install BATS (required for testing)
brew install bats-core  # macOS
sudo apt-get install bats  # Ubuntu/Debian

# Run all tests
./_test/run_tests.sh

# Run tests with specific filter
cd _test && bats install.bats --filter "install_tool"
```

The test suite includes:

- Unit tests for all utility functions
- Integration tests for package manager detection
- Installation tests for each package manager type
- macOS configuration tests with defaults mocking
- Mocking framework to simulate external commands
- 65+ comprehensive tests covering all major functionality

### Handling `errexit` in Shell Scripts

The `install.sh` script uses `set -euo pipefail` for strict error handling, which is a best practice for production scripts. However, this can cause issues in certain scenarios:

1. **Testing**: When functions are sourced in test environments, commands that normally fail (like checking for non-existent commands) will cause the entire function to exit.

2. **Information Gathering**: Functions that check system state need to handle failures gracefully without exiting.

The script handles this by temporarily disabling `errexit` in functions that need to tolerate failures:

```bash
get_available_managers() {
  # Save current errexit setting and disable it
  local old_errexit
  old_errexit=$(set +o | grep errexit)
  set +e
  
  # ... function body that may have failing commands ...
  
  # Restore errexit setting before returning
  eval "$old_errexit"
  return 0
}
```

This pattern ensures:

- The function can complete even if some commands fail
- The original shell options are preserved
- The script maintains strict error handling elsewhere

## Inspiration

- [idcrook](https://github.com/idcrook/i-dotfiles) - elegant usage of GNU stow
- [Typecraft Dev](https://github.com/typecraft-dev/dotfiles) - because of the excellent YouTube video walkthroughs - "be a better nerd"
- [Omer Hamerman / DevOpsToolbox](https://github.com/omerxx/dotfiles) - again, a fan of the YouTube video walkthroughs
- [Christian Sutter](https://github.com/csutter/punkt) - I used to work with Christian, and learned lots from pair programming with him.
- [Rob / Tech Craft](https://www.youtube.com/@tech_craft/videos) - Not posted for a while, but excellent videos
