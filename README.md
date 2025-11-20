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

### Fresh macOS Installation

For a brand new Mac, use the bootstrap script:

```bash
# Create directory structure and clone
mkdir -p ~/Developer/personal
cd ~/Developer/personal
git clone https://github.com/nickromney/n-dotfiles.git
cd n-dotfiles

# Run bootstrap to install essential tools
./bootstrap.sh

# Then continue with regular installation
./install.sh -d        # Dry run to preview
./install.sh           # Install base tools
./install.sh -s        # Stow configurations
```

### Existing System

If you already have Homebrew and basic tools:

```bash
# Clone and enter directory
git clone https://github.com/nickromney/n-dotfiles.git ~/n-dotfiles
cd ~/n-dotfiles

# Install the default (personal) toolchain
make personal install

# Provision a work Mac
make work install

# Apply macOS tweaks (dock, defaults) for the active profile
make personal configure

# Or just install VSCode and extensions
make focus-vscode
```

## Using the Makefile

The Makefile provides convenient targets for different configurations:

Combine a profile (`personal`, `work`, or `common`) with an action (`install`, `update`, `stow`, `configure`). Order does not matter, so `make work install` equals `make install work`.

```bash
# Profile + action examples
make personal install     # Install personal apps and CLIs
make work update          # Update tooling for work machines
make stow work            # Symlink configs for the work profile
make personal configure   # Apply macOS defaults (dock, keyboard, etc.)
make install PROFILE=work # Alternate syntax using PROFILE env var
make focus-mas install    # Optional Mac App Store apps (after "purchasing" once)

# Focus targets (specific tool categories)
make focus-vscode         # VSCode and extensions
make focus-neovim         # Neovim and plugins
make focus-mas            # Mac App Store apps (requires App Store login)

# VSCode for different editors
VSCODE_CLI=cursor make focus-vscode  # Install extensions for Cursor

> **Note:** Mac App Store installs require you to sign in via the App Store app and click “Get” once per app before `make focus-mas install` (or any `mas install`) can succeed.
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
# Preferred workflow
make personal install        # or: make work install
make focus-mas install       # optional, run after clicking "Get" in App Store
make stow personal           # symlink dotfiles
make personal configure      # apply macOS settings

# Direct install.sh usage (advanced/CI)
./install.sh              # Install packages only
./install.sh -s           # Install packages and stow configurations
./install.sh -d -s        # Preview changes
./install.sh -s -f        # Force stow
./install.sh -u           # Update installed packages
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

# Equivalent Makefile helper
make personal configure
```

See [_macos/README.md](_macos/README.md) for detailed macOS configuration options.

## 1Password Integration

This repository includes comprehensive 1Password integration for secure credential and configuration management.

### SSH Configuration Management

The `setup-ssh-from-1password.sh` script manages SSH configuration with security by default:

#### Default (Safe) Mode

```bash
# Download SSH config + public keys only (private keys stay in 1Password)
./setup-ssh-from-1password.sh

# Check what's available without downloading
./setup-ssh-from-1password.sh --dry-run
```

In safe mode:

- Downloads SSH config from 1Password (stored as Secure Note)
- Downloads **public keys only** for reference
- Private keys remain in 1Password
- Uses 1Password SSH Agent for authentication

#### Unsafe Mode (When 1Password SSH Agent Isn't Available)

```bash
# Download private keys (requires explicit confirmation)
./setup-ssh-from-1password.sh --unsafe
```

Use unsafe mode when:

- 1Password SSH Agent cannot be installed in your environment
- You're using a restricted system without agent support
- You need keys for backup/migration purposes

### Git Configuration Management

The `setup-gitconfig-from-1password.sh` script manages work-specific Git configurations:

```bash
# Download work Git config from 1Password
./setup-gitconfig-from-1password.sh

# Check availability without downloading
./setup-gitconfig-from-1password.sh --dry-run
```

This allows you to:

- Store work-specific Git config in 1Password
- Automatically apply it to `~/Developer/work/.gitconfig_include`
- Keep work email and GitHub Enterprise settings secure
- Use `includeIf` in main `.gitconfig` for automatic switching

### AWS Credentials Helper

The `aws/.aws/aws-1password` script provides on-demand AWS credential fetching:

```bash
# Configure AWS CLI to use 1Password
aws configure set credential_process "$HOME/.aws/aws-1password --username default"

# For different profiles
aws configure set credential_process "$HOME/.aws/aws-1password --username tfcli" --profile terraform
```

This approach:

- Never stores AWS credentials on disk
- Fetches credentials from 1Password when needed
- Works seamlessly with AWS CLI and SDKs
- Supports multiple AWS accounts/profiles

### Setting Up 1Password Items

#### SSH Keys

1. Open 1Password and create new item → SSH Key
2. Name it exactly as expected by the script:
   - `github_personal_authentication`
   - `github_personal_signing`
   - `aws_work_2024_client_1`
   - `github_work_2025_client_1`
3. Paste your private key
4. Save to "Private" vault (or adjust `VAULT` in script)

#### SSH Config

1. Create new item → Secure Note
2. Name it: `SSH Config`
3. Paste your complete SSH configuration
4. Save to "Private" vault

#### Git Config

1. Create new item → Secure Note
2. Name it: `work .gitconfig_include`
3. Add your work-specific Git configuration:

   ```ini
   [url "github-work:OrgName/"]
     insteadOf = git@github.com:OrgName/
   [user]
     email = work@company.com
   ```

4. Save to "Private" vault

#### AWS Credentials

1. Create new item → API Credential (or custom item)
2. Name it based on your mapping (e.g., `AWSCredsUsernameDefault`)
3. Add fields:
   - `ACCESS_KEY`: Your AWS Access Key ID
   - `SECRET_KEY`: Your AWS Secret Access Key
4. Save to "CLI" vault (or adjust in script)

### Security Benefits

- **No secrets in version control**: All sensitive data stays in 1Password
- **Encrypted at rest**: 1Password handles all encryption
- **Audit trail**: 1Password logs all access to credentials
- **Easy rotation**: Update credentials in one place
- **Team sharing**: Safely share vaults with team members
- **MFA protection**: Additional security with 1Password's MFA

## Configuration Structure

The `_configs/` directory uses a layered approach:

```text
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

## All Available Configurations

### Tool Configurations (_configs/)

| Configuration | Type | Description | Use Case |
|--------------|------|-------------|----------|
| **focus/ai** | Focus | AI/ML tools (ollama, etc.) | AI development |
| **focus/container-base** | Focus | Podman and container tools | Container development |
| **focus/kubernetes** | Focus | K8s tools (kubectl, k9s, helm) | Kubernetes management |
| **focus/neovim** | Focus | Extended Neovim plugins | Advanced vim setup |
| **focus/python** | Focus | Python dev tools (uv, ruff) | Python development with Rust-based tooling |
| **focus/rust** | Focus | Rust toolchain and utilities | Rust development |
| **focus/typescript** | Focus | Node.js, TypeScript, Biome | JavaScript/TypeScript dev with Rust-based linting |
| **focus/vscode** | Focus | VSCode + 38 extensions | Full VSCode development |
| **host/common** | Host | Common Mac apps (Ghostty, VSCode, Obsidian) | Standard Mac productivity |
| **host/personal** | Host | Personal additions (games, media apps) | Personal Mac extras |
| **host/work** | Host | Work-specific tools | Work Mac requirements |
| **shared/data-tools** | Shared | Data processing (jq, yq, csvlens) | JSON/YAML/CSV manipulation |
| **shared/file-tools** | Shared | File management (eza, tree, etc.) | Directory navigation |
| **shared/git** | Shared | Git tools (delta, lazygit, gh CLI) | Version control essentials |
| **shared/neovim** | Shared | Neovim and plugins | Text editor setup |
| **shared/network** | Shared | Network utilities (httpie, curlie, etc.) | API testing and network debugging |
| **shared/search** | Shared | Search tools (ripgrep, fzf, fd, etc.) | File and text searching |
| **shared/shell** | Shared | Shell utilities (zsh, starship, atuin, etc.) | Essential for all setups |

### macOS System Settings (_macos/)

| Configuration | Description | Key Settings |
|--------------|-------------|--------------|
| **personal.yaml** | Personal Mac settings | Natural scroll, dock apps, keyboard shortcuts |
| **work.yaml** | Work Mac settings | Corporate defaults, security settings |

### Makefile Targets (Convenient Combinations)

| Target | Includes | Purpose |
|--------|----------|---------|
| **make common install** | All shared/ + host/common | Essential Mac setup |
| **make focus-ai** | focus/ai | AI/ML development tools |
| **make focus-container-base** | focus/container-base | Podman and container tools |
| **make focus-containers** | focus/containers | Podman container tools |
| **make focus-kubernetes** | focus/kubernetes | Kubernetes toolchain |
| **make focus-neovim** | focus/neovim | Enhanced Neovim |
| **make focus-python** | focus/python | Python development |
| **make focus-rust** | focus/rust | Rust development |
| **make focus-typescript** | focus/typescript | TypeScript/Node.js |
| **make focus-vscode** | focus/vscode | VSCode + extensions |
| **make focus-mas** | focus/mas | Optional Mac App Store apps (requires prior purchase) |
| **make personal install** | Shared + host/common + host/personal + focus/containers + focus/kubernetes + focus/vscode | Full personal Mac |
| **make work install** | Shared + host/common + host/work + focus/containers + focus/kubernetes + focus/vscode | Work laptop tooling |
| **make work-setup** | Runs setup-work-mac.sh | Legacy scripted work setup |

### Quick Setup Guide

For a new personal Mac (like yours):

```bash
# 1. Install base tools and personal apps
make personal install

# 2. Optional: install Mac App Store apps once you're signed in + clicked "Get"
make focus-mas install

# 3. Create configuration symlinks
make personal stow

# 4. Apply macOS system settings (mouse scroll, dock, etc.)
make personal configure

# Or stow + configure together:
make personal stow && make personal configure
```

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
